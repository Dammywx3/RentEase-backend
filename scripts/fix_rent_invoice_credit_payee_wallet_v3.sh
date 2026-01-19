#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p scripts/.bak

SVC="src/services/rent_invoices.service.ts"
WALLET_UTIL="src/utils/wallets.ts"

backup() {
  local f="$1"
  if [ -f "$f" ]; then
    cp -v "$f" "scripts/.bak/$(basename "$f").bak.$TS" >/dev/null
    echo "✅ backup -> scripts/.bak/$(basename "$f").bak.$TS"
  fi
}

backup "$SVC"
backup "$WALLET_UTIL"

# ---- 1) Ensure wallets util exists
mkdir -p "$(dirname "$WALLET_UTIL")"
cat > "$WALLET_UTIL" <<'TS'
import type { PoolClient } from "pg";

export async function ensureWalletAccount(
  client: PoolClient,
  args: {
    organizationId: string;
    userId: string | null;
    currency: string;
    isPlatformWallet: boolean;
  }
): Promise<string> {
  const { rows: found } = await client.query<{ id: string }>(
    `
    SELECT id
    FROM public.wallet_accounts
    WHERE organization_id = $1::uuid
      AND user_id IS NOT DISTINCT FROM $2::uuid
      AND currency = $3::text
      AND is_platform_wallet = $4::boolean
    ORDER BY created_at ASC
    LIMIT 1;
    `,
    [args.organizationId, args.userId, args.currency, args.isPlatformWallet]
  );

  if (found[0]?.id) return found[0].id;

  const { rows: created } = await client.query<{ id: string }>(
    `
    INSERT INTO public.wallet_accounts (
      organization_id,
      user_id,
      currency,
      is_platform_wallet
    )
    VALUES ($1::uuid, $2::uuid, $3::text, $4::boolean)
    ON CONFLICT (organization_id, user_id, currency, is_platform_wallet)
    DO UPDATE SET organization_id = EXCLUDED.organization_id
    RETURNING id;
    `,
    [args.organizationId, args.userId, args.currency, args.isPlatformWallet]
  );

  if (!created[0]?.id) throw new Error("ensureWalletAccount: failed to create wallet_account");
  return created[0].id;
}
TS
echo "✅ wrote: $WALLET_UTIL"

# ---- 2) Auto-detect payee column in tenancies
PAYEE_COL="$(
  PAGER=cat psql -d "${DB_NAME:-rentease}" -Atc "
    select column_name
    from information_schema.columns
    where table_schema='public'
      and table_name='tenancies'
      and column_name in (
        'landlord_id',
        'owner_id',
        'landlord_user_id',
        'owner_user_id',
        'property_owner_id',
        'agent_id'
      )
    order by
      case column_name
        when 'landlord_id' then 1
        when 'owner_id' then 2
        when 'landlord_user_id' then 3
        when 'owner_user_id' then 4
        when 'property_owner_id' then 5
        when 'agent_id' then 6
        else 99
      end
    limit 1;
  " 2>/dev/null | tr -d '[:space:]'
)"

if [ -z "${PAYEE_COL:-}" ]; then
  echo "❌ Could not auto-detect a payee column on public.tenancies."
  echo "   Run: psql -d \"$DB_NAME\" -c \"\\d public.tenancies\""
  echo "   Then tell me which column is the landlord/owner user id."
  exit 1
fi

echo "✅ detected payee column: public.tenancies.${PAYEE_COL}"

# ---- 3) Patch ONLY the payee resolver + wallet tx part in rent_invoices.service.ts
python3 - <<PY
import re
from pathlib import Path

svc_path = Path("${SVC}")
txt = svc_path.read_text(encoding="utf-8")

# Ensure resolver exists or replace it
resolver_pat = re.compile(r"async function resolveRentInvoicePayeeUserId\\([\\s\\S]*?\\n\\}", re.M)
new_resolver = f"""async function resolveRentInvoicePayeeUserId(
  client: PoolClient,
  invoiceId: string,
  organizationId: string
): Promise<string> {{
  const r = await client.query<{{ payee_user_id: string }}>(
    \`
    SELECT t.{PAYEE_COL} AS payee_user_id
    FROM public.rent_invoices ri
    JOIN public.tenancies t ON t.id = ri.tenancy_id
    WHERE ri.id = $1::uuid
      AND ri.organization_id = $2::uuid
      AND ri.deleted_at IS NULL
    LIMIT 1;
    \`,
    [invoiceId, organizationId]
  );

  const payee = r.rows[0]?.payee_user_id;
  if (!payee) throw new Error("Cannot resolve payee_user_id for invoice " + invoiceId);
  return payee;
}}"""

if resolver_pat.search(txt):
    txt = resolver_pat.sub(new_resolver, txt, count=1)
else:
    # Insert resolver near top (after imports)
    # Find last import line
    m = list(re.finditer(r"^import .*?;\\s*$", txt, re.M))
    if not m:
        raise SystemExit("ERROR: Could not find import section to inject resolver.")
    insert_at = m[-1].end()
    txt = txt[:insert_at] + "\\n\\n" + new_resolver + "\\n" + txt[insert_at:]

# Replace wallet tx insert block inside payRentInvoice to use payeeWalletId (not platform wallet)
# We'll remove any platform wallet lookup and replace the whole wallet section with a clean one.

# 1) remove platform wallet SELECT block if present
txt = re.sub(
    r"\\n\\s*//\\s*4\\)\\s*Wallet transaction[\\s\\S]*?(?=\\n\\s*//\\s*5\\)\\s*Mark invoice paid)",
    "\\n  // 4) Wallet transaction (credit PAYEE wallet, reference_type='rent_invoice')\\n"
    "  const payeeUserId = await resolveRentInvoicePayeeUserId(client, invoice.id, invoice.organization_id);\\n"
    "  const payeeWalletId = await ensureWalletAccount(client, {\\n"
    "    organizationId: invoice.organization_id,\\n"
    "    userId: payeeUserId,\\n"
    "    currency,\\n"
    "    isPlatformWallet: false,\\n"
    "  });\\n\\n"
    "  await client.query(\\n"
    "    `\\n"
    "    INSERT INTO public.wallet_transactions (\\n"
    "      organization_id,\\n"
    "      wallet_account_id,\\n"
    "      txn_type,\\n"
    "      reference_type,\\n"
    "      reference_id,\\n"
    "      amount,\\n"
    "      currency,\\n"
    "      note\\n"
    "    )\\n"
    "    VALUES (\\n"
    "      $1::uuid,\\n"
    "      $2::uuid,\\n"
    "      'credit_payee'::wallet_transaction_type,\\n"
    "      'rent_invoice',\\n"
    "      $3::uuid,\\n"
    "      $4::numeric,\\n"
    "      $5::text,\\n"
    "      $6::text\\n"
    "    )\\n"
    "    ON CONFLICT DO NOTHING;\\n"
    "    `,\\n"
    "    [\\n"
    "      invoice.organization_id,\\n"
    "      payeeWalletId,\\n"
    "      invoice.id,\\n"
    "      amount,\\n"
    "      currency,\\n"
    "      `Rent payment for invoice ${invoice.invoice_number ?? invoice.id}`,\\n"
    "    ]\\n"
    "  );\\n\\n",
    txt,
    count=1
)

svc_path.write_text(txt, encoding="utf-8")
print("✅ patched payee resolver + wallet tx to use payeeWalletId (non-platform)")
PY

echo ""
echo "== DONE =="
echo "➡️ Restart: npm run dev"
echo ""
echo "➡️ IMPORTANT: Test with a NEW invoice (old paid ones won't change)."
