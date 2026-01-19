#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVC="$ROOT/src/services/rent_invoices.service.ts"

echo "== Patch rent_invoices.service.ts (wallet tx -> PAYEE wallet, credit_payee) =="

if [ ! -f "$SVC" ]; then
  echo "ERROR: Not found: $SVC"
  exit 1
fi

mkdir -p "$ROOT/scripts/.bak"
TS="$(date +%Y%m%d_%H%M%S)"
cp "$SVC" "$ROOT/scripts/.bak/rent_invoices.service.ts.bak.$TS"
echo "✅ backup -> scripts/.bak/rent_invoices.service.ts.bak.$TS"

python3 - <<'PY'
from pathlib import Path
import re

svc = Path("src/services/rent_invoices.service.ts")
txt = svc.read_text(encoding="utf-8")

# 1) Ensure we use credit_payee enum value (not 'credit' or other)
txt2 = txt.replace("'credit'::wallet_transaction_type", "'credit_payee'::wallet_transaction_type")
txt2 = txt2.replace("'credit'", "'credit_payee'")  # safety if someone used plain string

# 2) Replace any platform-wallet based insertion block with payee wallet insertion.
# We'll search for the wallet_transactions insert block inside payRentInvoice and ensure it uses payeeWalletId.
pattern = re.compile(
    r"""
    (//\s*4\)\s*.*?\n)                                   # comment line for step 4
    (?P<body>.*?)
    (//\s*5\)\s*Mark\s+invoice\s+paid)                   # step 5 marker
    """,
    re.DOTALL | re.VERBOSE
)

m = pattern.search(txt2)
if not m:
    raise SystemExit("ERROR: Could not locate Step 4/5 section in payRentInvoice().")

body = m.group("body")

# We want to ensure body contains:
# - resolveRentInvoicePayeeUserId(...)
# - ensureWalletAccount(...)
# - INSERT INTO public.wallet_transactions uses payeeWalletId
need_snips = ["resolveRentInvoicePayeeUserId", "ensureWalletAccount", "payeeWalletId", "INSERT INTO public.wallet_transactions"]
missing = [s for s in need_snips if s not in body]

# If already correct, just write any credit_payee replacements and exit ok.
if not missing:
    svc.write_text(txt2, encoding="utf-8")
    print("✅ Already has payee wallet credit block. (Applied any credit_payee string fixes.)")
    raise SystemExit(0)

# Otherwise, rebuild the entire Step 4 block safely.
# Keep Step 4 comment line but replace the content up to Step 5 marker.
step4_line = m.group(1)
step5_marker = "// 5) Mark invoice paid"

new_step4 = step4_line + r"""
  // 4) Credit PAYEE wallet (not platform wallet)
  const payeeUserId = await resolveRentInvoicePayeeUserId(
    client,
    invoice.id,
    invoice.organization_id
  );

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

""" + step5_marker

# Reconstruct file:
start = txt2[:m.start()]
end = txt2[m.end():]  # already includes the original step5 marker text, but we included marker in new_step4, so remove duplication
# Our regex consumed step5 marker, but not the actual code after it.
# "end" currently begins right after the step5 marker string.
# We'll prepend the step5 marker string (already in new_step4), so keep end as-is.
txt3 = start + new_step4 + end

svc.write_text(txt3, encoding="utf-8")
print("✅ Patched Step 4 wallet credit block to use PAYEE wallet + credit_payee.")
PY

echo "---- sanity checks"
grep -n "resolveRentInvoicePayeeUserId" "$SVC" >/dev/null && echo "✅ resolveRentInvoicePayeeUserId referenced"
grep -n "ensureWalletAccount" "$SVC" >/dev/null && echo "✅ ensureWalletAccount referenced"
grep -n "credit_payee" "$SVC" >/dev/null && echo "✅ credit_payee present"
grep -n "INSERT INTO public.wallet_transactions" "$SVC" >/dev/null && echo "✅ wallet_transactions insert present"

echo ""
echo "== DONE =="
echo "➡️ Restart server: npm run dev"
echo "➡️ Then generate & pay a NEW invoice (old rows won't change)."
