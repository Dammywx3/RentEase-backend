#!/usr/bin/env bash
set -euo pipefail

FILE="src/routes/index.ts"
if [[ ! -f "$FILE" ]]; then
  echo "ERROR: $FILE not found"
  exit 1
fi

TS=$(date +"%Y%m%d_%H%M%S")
BK=".patch_backups/${TS}"
mkdir -p "$BK"
cp "$FILE" "$BK/index.ts.bak"
echo "✅ Backup: $BK/index.ts.bak"

# If already registered, stop
if rg -n 'register\(payoutRoutes' "$FILE" >/dev/null 2>&1; then
  echo "✅ payoutRoutes already registered. No changes."
  exit 0
fi

# Insert after purchases registration
perl -0777 -i -pe 's/(await\s+v1\.register\(\s*purchasesRoutes\s*,\s*\{\s*prefix:\s*"\/purchases"\s*\}\s*\);\s*)/\1\n      \/\/ ✅ Payouts\n      await v1.register(payoutRoutes, { prefix: "\/payouts" });\n/s' "$FILE"

# Verify it worked
if ! rg -n 'register\(payoutRoutes' "$FILE" >/dev/null 2>&1; then
  echo "ERROR: Could not insert payoutRoutes registration automatically."
  echo "Open $FILE and add:"
  echo 'await v1.register(payoutRoutes, { prefix: "/payouts" });'
  exit 1
fi

echo "✅ Registered payoutRoutes in $FILE"
