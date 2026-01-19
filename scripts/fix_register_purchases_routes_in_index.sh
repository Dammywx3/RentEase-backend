#!/usr/bin/env bash
set -eo pipefail

FILE="src/routes/index.ts"
[ -f "$FILE" ] || { echo "❌ Missing: $FILE"; exit 1; }

mkdir -p scripts/.bak
ts="$(date +%Y%m%d_%H%M%S)"
cp "$FILE" "scripts/.bak/routes.index.ts.bak.$ts"
echo "✅ backup -> scripts/.bak/routes.index.ts.bak.$ts"

# 1) Ensure import exists
if ! grep -q "purchasesRoutes" "$FILE"; then
  # add import near other imports
  awk '
    BEGIN{added=0}
    /^import .*rentInvoicesRoutes/ && added==0 {
      print
      print "import purchasesRoutes from \"./purchases.routes.js\";"
      added=1
      next
    }
    {print}
  ' "$FILE" > /tmp/index.ts.$$ && mv /tmp/index.ts.$$ "$FILE"
  echo "✅ Added import purchasesRoutes"
else
  echo "ℹ️ purchasesRoutes import already present"
fi

# 2) Ensure registerRoutes registers it
if ! grep -q "app.register(purchasesRoutes" "$FILE"; then
  # add near other route registrations (after rent invoices is fine)
  awk '
    BEGIN{added=0}
    /await app.register\(rentInvoicesRoutes\);/ && added==0 {
      print
      print "  await app.register(purchasesRoutes);"
      added=1
      next
    }
    {print}
  ' "$FILE" > /tmp/index.ts.$$ && mv /tmp/index.ts.$$ "$FILE"
  echo "✅ Registered purchasesRoutes in registerRoutes()"
else
  echo "ℹ️ purchasesRoutes already registered"
fi

echo "✅ PATCHED: $FILE"
echo "NEXT:"
echo "  1) Restart server: npm run dev"
echo "  2) Test route:"
echo "     curl -sS -X POST \"$API/v1/purchases/$PURCHASE_ID/pay\" -H \"content-type: application/json\" -H \"authorization: Bearer $TOKEN\" -H \"x-organization-id: $ORG_ID\" -d '{\"paymentMethod\":\"card\",\"amount\":2000}' | jq"
