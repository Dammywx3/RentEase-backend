#!/usr/bin/env bash
set -euo pipefail

echo "ROOT=$(pwd)"
mkdir -p scripts/.bak

AUTH="src/middleware/auth.middleware.ts"
if [ -f "$AUTH" ]; then
  ts="$(date +%Y%m%d_%H%M%S)"
  cp "$AUTH" "scripts/.bak/auth.middleware.ts.bak.$ts"
  echo "✅ backup -> scripts/.bak/auth.middleware.ts.bak.$ts"

  # Remove the bad import line (if present)
  perl -i -pe 's/^\s*import\s+purchasesRoutes\s+from\s+["'\''].*purchases\.routes\.(js|ts)["'\'']\s*;\s*\n//m' "$AUTH" || true

  # Remove the bad fastify.register(...) line (if present)
  perl -i -pe 's/^\s*fastify\.register\(\s*purchasesRoutes\s*\)\s*;\s*\n//m' "$AUTH" || true

  echo "✅ PATCHED: removed purchasesRoutes usage from $AUTH"
else
  echo "⚠️ Not found: $AUTH (skipping)"
fi

# Find likely entry file that registers v1 routes
CANDIDATES=(
  "src/app.ts"
  "src/server.ts"
  "src/index.ts"
  "src/main.ts"
  "src/api/index.ts"
  "src/api/app.ts"
  "src/api/server.ts"
  "src/routes/v1.routes.ts"
  "src/routes/index.ts"
)

ENTRY=""
for f in "${CANDIDATES[@]}"; do
  if [ -f "$f" ]; then
    ENTRY="$f"
    break
  fi
done

# If not found, try to locate by searching for /v1/me or prefix '/v1'
if [ -z "$ENTRY" ]; then
  ENTRY="$(grep -RIl --exclude-dir=node_modules --exclude-dir=dist '/v1/me' src 2>/dev/null | head -n 1 || true)"
fi
if [ -z "$ENTRY" ]; then
  ENTRY="$(grep -RIl --exclude-dir=node_modules --exclude-dir=dist "prefix:.*'/v1'" src 2>/dev/null | head -n 1 || true)"
fi
if [ -z "$ENTRY" ]; then
  ENTRY="$(grep -RIl --exclude-dir=node_modules --exclude-dir=dist 'prefix:.*"/v1"' src 2>/dev/null | head -n 1 || true)"
fi

if [ -z "$ENTRY" ]; then
  echo ""
  echo "❌ Could not auto-find your Fastify entry/v1 router file."
  echo "Run these and paste output:"
  echo "  ls -la src"
  echo "  grep -RIn \"/v1/me\" src | head -n 30"
  echo "  grep -RIn \"prefix:.*v1\" src | head -n 30"
  exit 1
fi

ts="$(date +%Y%m%d_%H%M%S)"
cp "$ENTRY" "scripts/.bak/$(basename "$ENTRY").bak.$ts"
echo "✅ Found entry file: $ENTRY"
echo "✅ backup -> scripts/.bak/$(basename "$ENTRY").bak.$ts"

# Ensure import exists (path assumes your route is at src/routes/purchases.routes.ts)
if ! grep -q "purchasesRoutes" "$ENTRY"; then
  # insert after first import line
  perl -0777 -i -pe 's/(^import .*;\n)/$1import purchasesRoutes from ".\/routes\/purchases.routes.js";\n/m' "$ENTRY" || true
fi

# Register under /v1 if entry file uses prefix
# We'll try to detect a v1 plugin register block.
if grep -q "prefix:.*\/v1" "$ENTRY"; then
  # If there is a register call with prefix /v1, ensure purchasesRoutes is registered inside that plugin or after prefix register.
  # Simple approach: append a v1-prefixed registration if not present.
  if ! grep -q "register(.*purchasesRoutes" "$ENTRY"; then
    perl -0777 -i -pe '
      if ($_ !~ /register\(\s*purchasesRoutes/) {
        # try to add after the first occurrence of prefix /v1 registration
        s/(register\([^;]*prefix:\s*[\"\x27]\/v1[\"\x27][^;]*\);\n)/$1fastify.register(purchasesRoutes, { prefix: "\/v1" });\n/s
          or $_ .= "\nfastify.register(purchasesRoutes, { prefix: \"/v1\" });\n";
      }
    ' "$ENTRY" || true
  fi
else
  # If no explicit /v1 prefix found, still register with /v1 prefix
  if ! grep -q "register(.*purchasesRoutes" "$ENTRY"; then
    echo "" >> "$ENTRY"
    echo "fastify.register(purchasesRoutes, { prefix: \"/v1\" });" >> "$ENTRY"
  fi
fi

echo "✅ PATCHED: registered purchasesRoutes with prefix /v1 in $ENTRY"

echo ""
echo "NEXT:"
echo "  1) Restart server: npm run dev"
echo "  2) Test route:"
echo "     curl -sS -X POST \"\$API/v1/purchases/\$PURCHASE_ID/pay\" -H \"content-type: application/json\" -H \"authorization: Bearer \$TOKEN\" -H \"x-organization-id: \$ORG_ID\" -d '{\"paymentMethod\":\"card\",\"amount\":2000}' | jq"
