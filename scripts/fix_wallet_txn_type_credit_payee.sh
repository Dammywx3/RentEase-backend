#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVC="$ROOT/src/services/rent_invoices.service.ts"

mkdir -p "$ROOT/scripts/.bak"
ts="$(date +%Y%m%d_%H%M%S)"
cp "$SVC" "$ROOT/scripts/.bak/rent_invoices.service.ts.bak.$ts"
echo "✅ backup -> scripts/.bak/rent_invoices.service.ts.bak.$ts"

python3 - <<'PY'
from pathlib import Path
p = Path("src/services/rent_invoices.service.ts")
txt = p.read_text(encoding="utf-8")

# Replace the invalid enum literal 'credit' with a valid enum value
txt2 = txt.replace("'credit'::wallet_transaction_type", "'credit_payee'::wallet_transaction_type")
txt2 = txt2.replace("::wallet_transaction_type)  -- credit", "::wallet_transaction_type)  -- credit_payee")

if txt2 == txt:
    # fallback: if it was inserted as plain 'credit' without casting
    txt2 = txt.replace("'credit'", "'credit_payee'")

p.write_text(txt2, encoding="utf-8")
print("✅ patched src/services/rent_invoices.service.ts to use credit_payee")
PY

echo "➡️ Restart server: npm run dev"
