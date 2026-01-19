#!/usr/bin/env bash
set -euo pipefail

FILE="src/routes/payouts.routes.ts"
[[ -f "$FILE" ]] || { echo "[ERROR] Missing $FILE"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
BK_DIR=".patch_backups/${TS}"
mkdir -p "$BK_DIR"
cp "$FILE" "$BK_DIR/payouts.routes.ts.bak"
echo "✅ Backup: $FILE -> $BK_DIR/payouts.routes.ts.bak"

# Fix only the payouts routes (not payout-accounts)
# 1) GET "/payouts" -> GET "/"
# 2) Any "/payouts/..." -> "/..."
perl -0777 -i -pe '
  s/(fastify\.(?:get|post|put|delete)\(\s*)\"\/payouts\"\s*,/\1\"\/\",/g;
  s/(fastify\.(?:get|post|put|delete)\(\s*)\"\/payouts\//\1\"\/"/g;

  s/(fastify\.(?:get|post|put|delete)\(\s*)'\''\/payouts'\''\s*,/\1'\''\/'\'',/g;
  s/(fastify\.(?:get|post|put|delete)\(\s*)'\''\/payouts\//\1'\''\/'/g;
' "$FILE"

echo "✅ Patched payouts route paths (removed double /payouts prefix)."

echo ""
echo "Now these should exist:"
echo "  GET  /v1/payouts"
echo "  POST /v1/payouts/request"
echo "  POST /v1/payouts/:payoutId/process"
echo ""
echo "DONE ✅"
