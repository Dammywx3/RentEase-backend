#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(pwd)"
BAK_DIR="scripts/.bak"
mkdir -p "$BAK_DIR"

ts_now() { date +"%Y%m%d_%H%M%S"; }

backup_file() {
  local f="$1"
  if [[ -f "$f" ]]; then
    local b="$BAK_DIR/$(basename "$f").bak.$(ts_now)"
    cp "$f" "$b"
    echo "✅ backup -> $b"
  fi
}

# 1) Create wallets util
UTIL="src/utils/wallets.ts"
mkdir -p "$(dirname "$UTIL")"
if [[ ! -f "$UTIL" ]]; then
  cat > "$UTIL" <<'TS'
import type { PoolClient } from "pg";

export async function ensureWalletAccount(
  client: PoolClient,
  params: {
    organizationId: string;
    userId: string | null;          // null for platform wallet
    currency: string;
    isPlatformWallet: boolean;
  }
): Promise<string> {
  const { organizationId, userId, currency, isPlatformWallet } = params;

  // NOTE: unique constraint exists on (organization_id, user_id, currency, is_platform_wallet)
  const found = await client.query<{ id: string }>(
    `
    select id
    from public.wallet_accounts
    where organization_id = $1::uuid
      and currency = $2
      and is_platform_wallet = $3
      and (
        ($4::uuid is null and user_id is null)
        or user_id = $4::uuid
      )
    limit 1;
    `,
    [organizationId, currency, isPlatformWallet, userId]
  );

  if (found.rowCount && found.rows[0]?.id) return found.rows[0].id;

  const ins = await client.query<{ id: string }>(
    `
    insert into public.wallet_accounts (organization_id, user_id, currency, is_platform_wallet)
    values ($1::uuid, $2::uuid, $3, $4)
    returning id;
    `,
    [organizationId, userId, currency, isPlatformWallet]
  );

  return ins.rows[0].id;
}
TS
  echo "✅ created $UTIL"
else
  echo "ℹ️ $UTIL already exists (skipping create)"
fi

# 2) Patch rent_invoices.service.ts
SVC="src/services/rent_invoices.service.ts"
if [[ ! -f "$SVC" ]]; then
  echo "❌ Cannot find $SVC"
  echo "   If your file name differs, update SVC path in this script."
  exit 1
fi

backup_file "$SVC"

python3 - <<'PY'
from pathlib import Path
import re
p = Path("src/services/rent_invoices.service.ts")
txt = p.read_text(encoding="utf-8")

# Ensure import exists
if "ensureWalletAccount" not in txt:
    # Try to inject into existing imports area
    # If you have a utils barrel, adjust as needed.
    inject = "import { ensureWalletAccount } from \"../utils/wallets\";\n"
    # Put after last import line
    m = re.search(r"^(import .*?;\s*)+", txt, flags=re.M)
    if m:
        end = m.end()
        txt = txt[:end] + inject + txt[end:]
    else:
        txt = inject + txt

# --- You MUST adjust this block to match your schema ---
# We need payee_user_id (landlord) for the invoice.
# Edit the SQL below if your tenancy table/column differs.
marker = "/* RENT-INVOICE PAYEE RESOLUTION */"
if marker not in txt:
    resolver = f"""
{marker}
async function resolveRentInvoicePayeeUserId(client: any, invoiceId: string, organizationId: string): Promise<string> {{
  // TODO: Adjust this query to match your schema:
  // - If you already have rent_invoices.payee_user_id, use that.
  // - Otherwise join to tenancies/properties to get the landlord/owner user id.
  //
  // Example assumes: rent_invoices.tenancy_id -> tenancies.id and tenancies.landlord_id exists.
  const r = await client.query<{{ payee_user_id: string }}>(
    `
    select t.landlord_id as payee_user_id
    from public.rent_invoices ri
    join public.tenancies t on t.id = ri.tenancy_id
    where ri.id = $1::uuid and ri.organization_id = $2::uuid
    limit 1;
    `,
    [invoiceId, organizationId]
  );

  if (!r.rowCount) throw new Error("Cannot resolve payee_user_id for invoice " + invoiceId);
  return r.rows[0].payee_user_id;
}}
"""
    # place near top (after imports)
    m = re.search(r"^(import .*?;\s*)+", txt, flags=re.M)
    if m:
        txt = txt[:m.end()] + resolver + txt[m.end():]
    else:
        txt = resolver + txt

# Now patch the wallet transaction insert:
# Goal: credit_payee must use payeeWalletId, not platformWalletId.
#
# We’ll look for an insert into wallet_transactions with txn_type 'credit_payee'
# and replace wallet_account_id assignment logic around it.
pattern = re.compile(
    r"""
    (//.*?\n|/\*.*?\*/\s*)*
    (?P<prefix>.*?)
    client\.query\(
    \s*`(?P<sql>[^`]*insert\s+into\s+public\.wallet_transactions[^`]*?)`
    """,
    re.IGNORECASE | re.DOTALL | re.VERBOSE
)

# Instead of risky deep SQL rewriting, we do a safer targeted replace:
# Replace occurrences of:
#   txn_type: 'credit_payee' paired with using platformWalletId
#
txt2 = txt

# 1) ensure platform wallet is still created (for fees later), but create payee wallet + use it.
# Insert this snippet once in the pay() flow.
if "resolveRentInvoicePayeeUserId(" in txt2 and "payeeWalletId" not in txt2:
    # Try to find where you compute organizationId/invoiceId/currency and platform wallet
    # We inject near the first ensure/create platform wallet occurrence or near invoice load.
    anchor = re.search(r"(const\s+platformWalletId\s*=.*?;\s*)", txt2, flags=re.DOTALL)
    inject_snippet = """
  const payeeUserId = await resolveRentInvoicePayeeUserId(client, invoiceId, organizationId);
  const payeeWalletId = await ensureWalletAccount(client, {
    organizationId,
    userId: payeeUserId,
    currency,
    isPlatformWallet: false,
  });
"""
    if anchor:
        insert_at = anchor.end()
        txt2 = txt2[:insert_at] + inject_snippet + txt2[insert_at:]
    else:
        # fallback: inject after invoice fetch if present
        inv = re.search(r"(const\s+invoice\s*=.*?;\s*)", txt2, flags=re.DOTALL)
        if inv:
            insert_at = inv.end()
            txt2 = txt2[:insert_at] + "\n" + inject_snippet + txt2[insert_at:]

# 2) Replace wallet_account_id used for credit_payee from platformWalletId to payeeWalletId
txt2 = re.sub(
    r"(wallet_account_id\s*:\s*)platformWalletId(\s*,\s*[\s\S]*?txn_type\s*:\s*['\"]credit_payee['\"])",
    r"\1payeeWalletId\2",
    txt2,
    flags=re.IGNORECASE
)

# 3) If your insert uses parameter array style, replace the variable in args.
txt2 = re.sub(
    r"(\[\s*organizationId\s*,\s*)platformWalletId(\s*,\s*['\"]credit_payee['\"])",
    r"\1payeeWalletId\2",
    txt2,
    flags=re.IGNORECASE
)

if txt2 == txt:
    # Not necessarily failure; file might be structured differently
    print("⚠️ Could not auto-patch wallet_account_id for credit_payee (file structure differs).")
    print("   Search in rent_invoices.service.ts for txn_type 'credit_payee' and ensure it uses payeeWalletId.")
else:
    p.write_text(txt2, encoding="utf-8")
    print("✅ patched src/services/rent_invoices.service.ts (credit_payee should credit payee wallet)")
PY

echo
echo "✅ Done."
echo "NEXT:"
echo "1) Open src/services/rent_invoices.service.ts and confirm the query inside resolveRentInvoicePayeeUserId() matches your schema."
echo "2) Restart API: npm run dev"
echo "3) Pay an invoice, then run:"
echo "   PAGER=cat psql -d \"$DB_NAME\" -c \"select wt.txn_type, wt.amount, wt.wallet_account_id, wa.user_id, wa.is_platform_wallet from public.wallet_transactions wt join public.wallet_accounts wa on wa.id=wt.wallet_account_id where wt.reference_type='rent_invoice' order by wt.created_at desc limit 5;\""
