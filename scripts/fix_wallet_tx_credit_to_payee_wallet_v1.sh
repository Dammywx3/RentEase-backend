#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p scripts/.bak

SVC="src/services/rent_invoices.service.ts"
UTIL="src/utils/wallets.ts"

cp "$SVC" "scripts/.bak/$(basename "$SVC").bak.$TS"
echo "✅ backup -> scripts/.bak/$(basename "$SVC").bak.$TS"

# Ensure wallets util has ensureWalletAccount
mkdir -p "$(dirname "$UTIL")"
if ! grep -q "export async function ensureWalletAccount" "$UTIL" 2>/dev/null; then
  cat > "$UTIL" <<'TS'
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
      organization_id, user_id, currency, is_platform_wallet
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
  echo "✅ wrote: $UTIL"
fi

python3 - <<'PY'
from pathlib import Path
import re

svc = Path("src/services/rent_invoices.service.ts")
txt = svc.read_text(encoding="utf-8")

# Ensure import exists
if 'ensureWalletAccount' not in txt:
    # try common patterns
    if 'from "../utils/wallets"' in txt:
        pass
    else:
        # add import near top
        txt = re.sub(
            r'^(import .*?;\s*)+',
            lambda m: m.group(0) + 'import { ensureWalletAccount } from "../utils/wallets.js";\n',
            txt,
            count=1,
            flags=re.M
        )

# Insert/replace resolver (properties.owner_id)
resolver = r"""async function resolveRentInvoicePayeeUserId\(
[\s\S]*?\n\}"""

new_resolver = """async function resolveRentInvoicePayeeUserId(
  client: any,
  invoiceId: string,
  organizationId: string
): Promise<string> {
  const r = await client.query<{ payee_user_id: string }>(
    `
    SELECT p.owner_id AS payee_user_id
    FROM public.rent_invoices ri
    JOIN public.properties p ON p.id = ri.property_id
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
}"""

if re.search(resolver, txt, flags=re.M):
    txt = re.sub(resolver, new_resolver, txt, count=1, flags=re.M)
else:
    # inject after imports
    imports = list(re.finditer(r"^import .*?;\s*$", txt, flags=re.M))
    if not imports:
        raise SystemExit("ERROR: cannot find imports to inject resolver")
    insert_at = imports[-1].end()
    txt = txt[:insert_at] + "\n\n" + new_resolver + "\n" + txt[insert_at:]

# Replace wallet tx block to use payee wallet (NOT platform wallet)
# We replace anything between "Wallet transaction" comment and "Mark invoice paid"
txt2 = re.sub(
    r"\n\s*//\s*4\)\s*Wallet transaction[\s\S]*?(?=\n\s*//\s*5\)\s*Mark invoice paid)",
    r"""
  // 4) Wallet transaction (credit PAYEE wallet, reference_type='rent_invoice')
  const payeeUserId = await resolveRentInvoicePayeeUserId(client, invoice.id, invoice.organization_id);

  const payeeWalletId = await ensureWalletAccount(client, {
    organizationId: invoice.organization_id,
    userId: payeeUserId,
    currency,
    isPlatformWallet: false,
  });

  await client.query(
    `
    INSERT INTO public.wallet_transactions (
      organization_id,
      wallet_account_id,
      txn_type,
      reference_type,
      reference_id,
      amount,
      currency,
      note
    )
    VALUES (
      $1::uuid,
      $2::uuid,
      'credit_payee'::wallet_transaction_type,
      'rent_invoice',
      $3::uuid,
      $4::numeric,
      $5::text,
      $6::text
    )
    ON CONFLICT DO NOTHING;
    `,
    [
      invoice.organization_id,
      payeeWalletId,
      invoice.id,
      amount,
      currency,
      `Rent payment for invoice ${invoice.invoice_number ?? invoice.id}`,
    ]
  );
""",
    txt,
    count=1,
    flags=re.M
)

if txt2 == txt:
    raise SystemExit("ERROR: Could not find wallet block to replace (missing '// 4) Wallet transaction' or '// 5) Mark invoice paid').")

svc.write_text(txt2, encoding="utf-8")
print("✅ patched rent_invoices.service.ts: wallet tx now credits PAYEE wallet")
PY

echo "== DONE =="
echo "➡️ Restart server: npm run dev"
echo "➡️ Then generate & pay a NEW invoice to verify user_id is populated."
