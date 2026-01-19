#!/usr/bin/env bash
set -euo pipefail

FILE="src/routes/index.ts"
TS="$(date +"%Y%m%d_%H%M%S")"
BK=".patch_backups/${TS}"
mkdir -p "$BK"
cp "$FILE" "$BK/index.ts.bak"
echo "✅ Backup: $BK/index.ts.bak"

# Already registered?
if rg -n 'v1\.register\(\s*payoutRoutes' "$FILE" >/dev/null 2>&1; then
  echo "✅ payoutRoutes already registered under v1. No changes."
  exit 0
fi

# Ensure import exists (you already have it, but just in case)
if ! rg -n 'from "\.\/payouts\.routes\.js"' "$FILE" >/dev/null 2>&1; then
  perl -i -pe 'if($.==1){print qq(import { payoutRoutes } from "./payouts.routes.js";\n)}' "$FILE"
fi

# Insert registration after purchases registration INSIDE v1 block
perl -0777 -i -pe 's/(await\s+v1\.register\(\s*purchasesRoutes\s*,\s*\{\s*prefix:\s*"\/purchases"\s*\}\s*\);\s*)/\1\n      \/\/ ✅ Payouts\n      await v1.register(payoutRoutes, { prefix: "\/payouts" });\n/s' "$FILE"

if ! rg -n 'v1\.register\(\s*payoutRoutes' "$FILE" >/dev/null 2>&1; then
  echo "❌ Could not auto-insert. Add this manually inside async function v1(v1) { ... } :"
  echo 'await v1.register(payoutRoutes, { prefix: "/payouts" });'
  exit 1
fi

echo "✅ Added v1.register(payoutRoutes, { prefix: \"/payouts\" })"
