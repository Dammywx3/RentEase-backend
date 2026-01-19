#!/usr/bin/env bash
set -eo pipefail

FILE="src/routes/index.ts"
[ -f "$FILE" ] || { echo "❌ Missing: $FILE"; exit 1; }

mkdir -p scripts/.bak
ts="$(date +%Y%m%d_%H%M%S)"
cp "$FILE" "scripts/.bak/routes.index.ts.bak.$ts"
echo "✅ backup -> scripts/.bak/routes.index.ts.bak.$ts"

# If purchases is registered without prefix, replace it with prefix /v1
if grep -qE "app\.register\(purchasesRoutes\);\s*$" "$FILE"; then
  perl -0777 -i -pe 's/await\s+app\.register\(purchasesRoutes\);\s*/await app.register(purchasesRoutes, { prefix: "\/v1" });\n/sg' "$FILE"
  echo "✅ Updated purchasesRoutes registration to prefix /v1"
else
  # If it's already with prefix, do nothing
  if grep -qE "app\.register\(purchasesRoutes,\s*\{\s*prefix:\s*\"\/v1\"\s*\}\)" "$FILE"; then
    echo "ℹ️ purchasesRoutes already registered with prefix /v1 (no change)"
  else
    echo "⚠️ Could not find a plain 'await app.register(purchasesRoutes);' line."
    echo "   Open $FILE and ensure you have:"
    echo '   await app.register(purchasesRoutes, { prefix: "/v1" });'
  fi
fi

echo "✅ PATCHED: $FILE"
echo "NEXT:"
echo "  1) Restart server: npm run dev"
echo "  2) Test pay:"
echo "     curl -sS -X POST \"$API/v1/purchases/$PURCHASE_ID/pay\" -H \"content-type: application/json\" -H \"authorization: Bearer $TOKEN\" -H \"x-organization-id: $ORG_ID\" -d '{\"paymentMethod\":\"card\",\"amount\":2000}' | jq"
echo "  3) Test list:"
echo "     curl -sS \"$API/v1/purchases\" -H \"authorization: Bearer $TOKEN\" -H \"x-organization-id: $ORG_ID\" | jq"
