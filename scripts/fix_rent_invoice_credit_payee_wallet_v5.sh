#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p scripts/.bak

SVC="src/services/rent_invoices.service.ts"
WALLET_UTIL="src/utils/wallets.ts"
DB="${DB_NAME:-rentease}"

backup() {
  local f="$1"
  if [ -f "$f" ]; then
    cp -v "$f" "scripts/.bak/$(basename "$f").bak.$TS" >/dev/null
    echo "✅ backup -> scripts/.bak/$(basename "$f").bak.$TS"
  fi
}

backup "$SVC"
backup "$WALLET_UTIL"

# 1) ensure wallets util exists
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
    RETURNING id;
    `,
    [args.organizationId, args.userId, args.currency, args.isPlatformWallet]
  );

  if (!created[0]?.id) throw new Error("ensureWalletAccount: failed to create wallet_account");
  return created[0].id;
}
TS
echo "✅ wrote: $WALLET_UTIL"

# 2) detect payee from properties/property_listings
PAYEE_SRC=""
PAYEE_COL=""

has_table() { PAGER=cat psql -d "$DB" -Atc "select to_regclass('public.$1') is not null;" 2>/dev/null | tr -d '[:space:]'; }

detect_payee() {
  local table="$1"
  local col
  col="$(PAGER=cat psql -d "$DB" -Atc "
    select column_name
    from information_schema.columns
    where table_schema='public'
      and table_name='${table}'
      and column_name in (
        'landlord_id','owner_id','owner_user_id','landlord_user_id','user_id','created_by','agent_id'
      )
    order by
      case column_name
        when 'landlord_id' then 1
        when 'owner_id' then 2
        when 'owner_user_id' then 3
        when 'landlord_user_id' then 4
        when 'user_id' then 5
        when 'created_by' then 6
        when 'agent_id' then 7
        else 99
      end
    limit 1;
  " 2>/dev/null | tr -d '[:space:]')"
  if [ -n "$col" ]; then
    PAYEE_SRC="$table"
    PAYEE_COL="$col"
    return 0
  fi
  return 1
}

if [ "$(has_table properties)" = "t" ]; then
  detect_payee "properties" || true
fi
if [ -z "$PAYEE_COL" ] && [ "$(has_table property_listings)" = "t" ]; then
  detect_payee "property_listings" || true
fi

if [ -z "$PAYEE_COL" ]; then
  echo "❌ Could not auto-detect payee user id column."
  echo "   Run and paste one:"
  echo "     PAGER=cat psql -d \"$DB\" -c \"\\d public.properties\""
  echo "     PAGER=cat psql -d \"$DB\" -c \"\\d public.property_listings\""
  exit 1
fi

echo "✅ detected payee from: public.${PAYEE_SRC}.${PAYEE_COL}"

# 3) patch service safely
python3 - <<'PY'
import re
from pathlib import Path

svc_path = Path("src/services/rent_invoices.service.ts")
txt = svc_path.read_text(encoding="utf-8")

payee_src = Path("scripts/.payee_src").read_text().strip() if Path("scripts/.payee_src").exists() else None
PY

python3 - <<'PY'
import re
from pathlib import Path

svc_path = Path("src/services/rent_invoices.service.ts")
txt = svc_path.read_text(encoding="utf-8")

payee_src = Path("scripts/.payee_src").read_text().strip()
payee_col = Path("scripts/.payee_col").read_text().strip()

# --- ensure ensureWalletAccount import exists
if "ensureWalletAccount" not in txt:
    txt = txt.replace('import { ensureWalletAccount } from "../utils/wallets";', 'import { ensureWalletAccount } from "../utils/wallets";')

# --- replace or insert resolver
resolver_pat = re.compile(r"async function resolveRentInvoicePayeeUserId\([\s\S]*?\n\}", re.M)

new_resolver = f"""async function resolveRentInvoicePayeeUserId(
  client: any,
  invoiceId: string,
  organizationId: string
): Promise<string> {{
  const r = await client.query<{{ payee_user_id: string }}>(
    `
    SELECT p.{payee_col} AS payee_user_id
    FROM public.rent_invoices ri
    JOIN public.{payee_src} p ON p.id = ri.property_id
    WHERE ri.id = $1::uuid
      AND ri.organization_id = $2::uuid
      AND ri.deleted_at IS NULL
    LIMIT 1;
    `,
    [invoiceId, organizationId]
  );

  const payee = r.rows[0]?.payee_user_id;
  if (!payee) throw new Error("Cannot resolve payee_user_id for invoice " + invoiceId);
  return payee;
}}"""

if resolver_pat.search(txt):
    txt = resolver_pat.sub(new_resolver, txt, count=1)
else:
    # insert after imports
    m = list(re.finditer(r"^import .*?;\s*$", txt, re.M))
    if not m:
        raise SystemExit("ERROR: Could not find import section to inject resolver.")
    insert_at = m[-1].end()
    txt = txt[:insert_at] + "\n\n" + new_resolver + "\n" + txt[insert_at:]

# --- replace wallet section inside payRentInvoice
txt = re.sub(
    r"\n\s*//\s*4\)\s*Wallet transaction[\s\S]*?(?=\n\s*//\s*5\)\s*Mark invoice paid)",
    "\n  // 4) Wallet transaction (credit PAYEE wallet, reference_type='rent_invoice')\n"
    "  const payeeUserId = await resolveRentInvoicePayeeUserId(client, invoice.id, invoice.organization_id);\n"
    "  const payeeWalletId = await ensureWalletAccount(client, {\n"
    "    organizationId: invoice.organization_id,\n"
    "    userId: payeeUserId,\n"
    "    currency,\n"
    "    isPlatformWallet: false,\n"
    "  });\n\n"
    "  await client.query(\n"
    "    `\n"
    "    INSERT INTO public.wallet_transactions (\n"
    "      organization_id,\n"
    "      wallet_account_id,\n"
    "      txn_type,\n"
    "      reference_type,\n"
    "      reference_id,\n"
    "      amount,\n"
    "      currency,\n"
    "      note\n"
    "    )\n"
    "    VALUES (\n"
    "      $1::uuid,\n"
    "      $2::uuid,\n"
    "      'credit_payee'::wallet_transaction_type,\n"
    "      'rent_invoice',\n"
    "      $3::uuid,\n"
    "      $4::numeric,\n"
    "      $5::text,\n"
    "      $6::text\n"
    "    )\n"
    "    ON CONFLICT DO NOTHING;\n"
    "    `,\n"
    "    [\n"
    "      invoice.organization_id,\n"
    "      payeeWalletId,\n"
    "      invoice.id,\n"
    "      amount,\n"
    "      currency,\n"
    "      `Rent payment for invoice ${invoice.invoice_number ?? invoice.id}`,\n"
    "    ]\n"
    "  );\n\n",
    txt,
    count=1
)

svc_path.write_text(txt, encoding="utf-8")
print("✅ patched resolver + wallet tx to credit PAYEE wallet (non-platform)")
PY

echo ""
echo "== DONE =="
echo "➡️ Restart server: npm run dev"
echo "➡️ IMPORTANT: test with a NEW invoice"
