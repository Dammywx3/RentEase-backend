#!/usr/bin/env bash
set -euo pipefail

FILE="src/services/purchase_payments.service.ts"
if [[ ! -f "$FILE" ]]; then
  echo "❌ Not found: $FILE"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p scripts/.bak
cp "$FILE" "scripts/.bak/purchase_payments.service.ts.bak.$TS"
echo "✅ backup -> scripts/.bak/purchase_payments.service.ts.bak.$TS"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("src/services/purchase_payments.service.ts")
s = p.read_text(encoding="utf-8")

# Replace the idempotent return that still returns the stale `purchase`
# We detect the block by the alreadyPaid:true return line.
pat = re.compile(
    r"""
    (\n[ \t]*)return\s*\{\s*
      purchase\s*,\s*
      alreadyPaid\s*:\s*true\s*,\s*
      platformFee\s*:\s*split\.platformFee\s*,\s*
      sellerNet\s*:\s*split\.payeeNet
    \s*\}\s*;\s*
    """,
    re.VERBOSE,
)

if not pat.search(s):
    raise SystemExit("❌ Could not find idempotent return with split.platformFee/split.payeeNet. Search for 'alreadyPaid: true' and rerun.")

def repl(m):
    indent = m.group(1)
    return (
        f"""{indent}const refreshed = await getPropertyPurchase(client, {{
{indent}  organizationId: args.organizationId,
{indent}  purchaseId: purchase.id,
{indent}}});

{indent}return {{ purchase: refreshed, alreadyPaid: true, platformFee: 0, sellerNet: 0 }};\n"""
    )

s, n = pat.subn(repl, s, count=1)
if n != 1:
    raise SystemExit("❌ Patch failed: did not replace idempotent return (unexpected).")

p.write_text(s, encoding="utf-8")
print("✅ Patched idempotent response to re-fetch purchase + return 0/0.")
PY

echo "✅ PATCHED: $FILE"
echo "NEXT:"
echo "  1) Restart server: npm run dev"
echo "  2) Call pay endpoint again"
