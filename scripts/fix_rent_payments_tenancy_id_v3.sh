#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVC="$ROOT/src/services/rent_invoices.service.ts"
BAK="$ROOT/scripts/.bak"
mkdir -p "$BAK"
ts="$(date +%Y%m%d_%H%M%S)"

cp "$SVC" "$BAK/rent_invoices.service.ts.bak.$ts"
echo "✅ backup -> scripts/.bak/rent_invoices.service.ts.bak.$ts"

python3 - <<'PY'
from pathlib import Path
import re

svc = Path("src/services/rent_invoices.service.ts")
txt = svc.read_text(encoding="utf-8")

# Find the rent_payments INSERT block and replace it with a SELECT-from-rent_invoices insert
pat = re.compile(
    r"""
    const\s+payRes\s*=\s*await\s+client\.query<\{ id:\s*string\s*\}>\(\s*
    `\s*
    INSERT\s+INTO\s+public\.rent_payments[\s\S]*?
    RETURNING\s+id;\s*
    `\s*,\s*
    \[[\s\S]*?\]\s*
    \)\s*;
    """,
    re.VERBOSE
)

replacement = r"""const payRes = await client.query<{ id: string }>(
    `
    INSERT INTO public.rent_payments (
      invoice_id,
      tenancy_id,
      tenant_id,
      property_id,
      organization_id,
      amount,
      currency,
      payment_method
    )
    SELECT
      $1::uuid AS invoice_id,
      ri.tenancy_id,
      ri.tenant_id,
      ri.property_id,
      ri.organization_id,
      $2::numeric AS amount,
      COALESCE(ri.currency, 'USD') AS currency,
      COALESCE($3, 'unknown') AS payment_method
    FROM public.rent_invoices ri
    WHERE ri.id = $1::uuid
      AND ri.deleted_at IS NULL
    RETURNING id;
    `,
    [args.invoiceId, amount, args.paymentMethod]
  );"""

new_txt, n = pat.subn(replacement, txt, count=1)
if n == 0:
    raise SystemExit("ERROR: Could not locate rent_payments INSERT block inside payRentInvoice().")

svc.write_text(new_txt, encoding="utf-8")
print("✅ Patched rent_payments insert to include tenancy_id/org/tenant/property via rent_invoices")
PY

echo "---- sanity checks"
grep -n "ri.tenancy_id" "$SVC" >/dev/null && echo "✅ tenancy_id source found"
grep -n "INSERT INTO public.rent_payments" "$SVC" >/dev/null && echo "✅ rent_payments insert found"

echo ""
echo "== DONE =="
echo "➡️ Restart server: npm run dev"
