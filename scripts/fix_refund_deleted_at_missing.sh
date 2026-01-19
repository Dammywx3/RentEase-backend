#!/usr/bin/env bash
set -euo pipefail

TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p scripts/.bak

FILES=(
  "src/services/purchase_refunds.service.ts"
  "src/services/ledger.service.ts"
)

for FILE in "${FILES[@]}"; do
  if [ -f "$FILE" ]; then
    cp "$FILE" "scripts/.bak/$(basename "$FILE").bak.$TS"
    echo "✅ backup -> scripts/.bak/$(basename "$FILE").bak.$TS"

    # Remove alias.deleted_at filters EXCEPT for pp.deleted_at (property_purchases alias usually "pp")
    perl -0777 -i -pe '
      s/\s+AND\s+(?!pp\.)[a-zA-Z_][a-zA-Z0-9_]*\.deleted_at\s+IS\s+NULL//g;
    ' "$FILE"

    echo "✅ patched: $FILE"
  else
    echo "⚠️ missing: $FILE (skipping)"
  fi
done

echo ""
echo "🔎 Typecheck..."
npx -y tsc -p tsconfig.json --noEmit
echo "✅ OK"
echo ""
echo "NEXT:"
echo "  1) restart: npm run dev"
echo "  2) retry refund endpoint"
