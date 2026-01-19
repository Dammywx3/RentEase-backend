#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(pwd)"
FILE="$REPO_ROOT/src/routes/index.ts"

if [[ ! -f "$FILE" ]]; then
  echo "[ERROR] Not found: $FILE"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
BK_DIR="$REPO_ROOT/.patch_backups/${TS}"
mkdir -p "$BK_DIR"

cp "$FILE" "$BK_DIR/index.ts.bak"
echo "✅ Backup: $FILE -> $BK_DIR/index.ts.bak"

# 1) Ensure correct import name
# - if they currently import payoutsRoutes, replace with payoutRoutes
# - if payoutRoutes import is commented out, uncomment it
perl -0777 -i -pe '
  s/import\s+\{\s*payoutsRoutes\s*\}\s+from\s+"\.\/payouts\.routes\.js";/import { payoutRoutes } from ".\/payouts.routes.js";/g;

  # Uncomment if someone has //import { payoutRoutes } ...
  s/\/\/\s*import\s+\{\s*payoutRoutes\s*\}\s+from\s+"\.\/payouts\.routes\.js";/import { payoutRoutes } from ".\/payouts.routes.js";/g;

  # If they have both, remove the plural one to avoid duplicates
  s/\nimport\s+\{\s*payoutsRoutes\s*\}\s+from\s+"\.\/payouts\.routes\.js";\s*\n/\n/g;
' "$FILE"

# 2) Ensure correct registration call
perl -0777 -i -pe '
  s/await\s+v1\.register\(\s*payoutsRoutes\s*,\s*\{\s*prefix:\s*"\/payouts"\s*\}\s*\);/await v1.register(payoutRoutes, { prefix: "\/payouts" });/g;
' "$FILE"

echo "✅ Patched index.ts to use payoutRoutes"

# 3) Show quick verification
echo "---- import lines ----"
rg -n "payoutRoutes|payoutsRoutes" "$FILE" || true

echo "---- register lines ----"
rg -n "register\\(payoutRoutes|register\\(payoutsRoutes" "$FILE" || true

echo "DONE ✅"
