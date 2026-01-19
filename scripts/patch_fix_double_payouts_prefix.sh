#!/usr/bin/env bash
set -euo pipefail

FILE="src/routes/payouts.routes.ts"
[[ -f "$FILE" ]] || { echo "[ERROR] Missing $FILE"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
BK_DIR=".patch_backups/${TS}"
mkdir -p "$BK_DIR"
cp "$FILE" "$BK_DIR/payouts.routes.ts.bak"
echo "✅ Backup: $FILE -> $BK_DIR/payouts.routes.ts.bak"

# Replace only route declarations that start with "/payouts"
perl -0777 -i -pe '
  s/(fastify\.(?:get|post|put|delete)\(\s*)\"\/payouts\"/\1\"\/\"/g;
  s/(fastify\.(?:get|post|put|delete)\(\s*)\"\/payouts\//\1\"\/"/g;
  s/(fastify\.(?:get|post|put|delete)\(\s*)'\''\/payouts'\''/\1'\''\/'\''/g;
  s/(fastify\.(?:get|post|put|delete)\(\s*)'\''\/payouts\//\1'\''\/'/g;
' "$FILE"

echo "✅ Patched route paths in $FILE"
rg -n 'fastify\.(get|post|put|delete)\(' "$FILE" || true
echo "DONE ✅"
