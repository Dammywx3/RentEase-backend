#!/usr/bin/env bash
set -euo pipefail

FILE="src/services/rent_invoices.service.ts"
[ -f "$FILE" ] || { echo "❌ Missing $FILE"; exit 1; }

ts="$(date +%Y%m%d_%H%M%S)"
bak="scripts/.bak/rent_invoices.service.ts.bak.$ts"
cp "$FILE" "$bak"
echo "✅ backup -> $bak"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("src/services/rent_invoices.service.ts")
txt = p.read_text(encoding="utf-8")

# 1) ensure round2 helper exists
if "function round2(" not in txt:
    # insert after imports block (after last import line)
    m = re.search(r"(^(?:import .*?\n)+)", txt, flags=re.M)
    if not m:
        print("❌ Could not find import block to insert round2()", file=sys.stderr)
        sys.exit(1)
    ins = m.group(1) + "\nfunction round2(n: number): number {\n  return Math.round((n + Number.EPSILON) * 100) / 100;\n}\n\n"
    txt = txt.replace(m.group(1), ins)

# 2) replace section 4 (wallet credit) with split logic
# we replace from the comment line starting with "// 4) Credit" up to just before "// 5) Mark invoice paid"
pattern = r"(\n\s*//\s*4\)\s*.*?\n)([\s\S]*?)(\n\s*//\s*5\)\s*Mark invoice paid)"
m = re.search(pattern, txt)
if not m:
    print("❌ Could not find section markers for step 4/5 in payRentInvoice().", file=sys.stderr)
    print("   Make sure your file contains comments like:", file=sys.stderr)
    print("   // 4) Credit PAYEE wallet ...", file=sys.stderr)
    print("   // 5) Mark invoice paid", file=sys.stderr)
    sys.exit(1)

header = m.group(1)
footer = m.group(3)

replacement_block = r"""
  // 4) Wallet split:
  //    - 2.5% platform fee to PLATFORM wallet (user_id NULL, is_platform_wallet=true)
  //    - 97.5% to PAYEE wallet (owner_id)
  const feeRate = 0.025;
  const platformFee = round2(amount * feeRate);
  const payeeNet = round2(amount - platformFee);

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

  const platformWalletId = await ensureWalletAccount(client, {
    organizationId: invoice.organization_id,
    userId: null,
    currency,
    isPlatformWallet: true,
  });

  // credit payee (NET)
  if (payeeNet > 0) {
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
        payeeNet,
        currency,
        `Rent payment (net) for invoice ${invoice.invoice_number ?? invoice.id}`,
      ]
    );
  }

  // credit platform (FEE)
  if (platformFee > 0) {
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
        'credit_platform_fee'::wallet_transaction_type,
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
        platformWalletId,
        invoice.id,
        platformFee,
        currency,
        `Platform fee (2.5%) for invoice ${invoice.invoice_number ?? invoice.id}`,
      ]
    );
  }
"""

new_txt = txt[:m.start()] + header + replacement_block + footer + txt[m.end():]

p.write_text(new_txt, encoding="utf-8")
print("✅ patched: payRentInvoice() now splits 2.5% platform fee + payee net")
PY

echo ""
echo "== DONE =="
echo "➡️ Restart server: npm run dev"
echo "➡️ Then generate + pay a NEW invoice (old paid invoices won't change)."
