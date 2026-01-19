#!/usr/bin/env bash
set -euo pipefail

FILE="src/routes/payouts.routes.ts"
[[ -f "$FILE" ]] || { echo "[ERROR] Missing $FILE"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
BK_DIR=".patch_backups/${TS}"
mkdir -p "$BK_DIR"
cp "$FILE" "$BK_DIR/payouts.routes.ts.bak"
echo "✅ Backup: $FILE -> $BK_DIR/payouts.routes.ts.bak"

# Remove double "/payouts" prefix inside the plugin.
# Because index.ts already registers it with prefix: "/payouts"
# So inside the plugin, routes should be:
#   GET  "/"               -> /v1/payouts
#   POST "/request"        -> /v1/payouts/request
#   POST "/:payoutId/process" -> /v1/payouts/:payoutId/process

perl -i -pe 's/fastify\.get\("\/payouts"\s*,/fastify.get("\/",/g' "$FILE"
perl -i -pe 's/fastify\.post\("\/payouts\/request"\s*,/fastify.post("\/request",/g' "$FILE"
perl -i -pe 's/"\/payouts\/:payoutId\/process"/"\/:payoutId\/process"/g' "$FILE"

echo "✅ Patched: removed inner /payouts prefix."
echo ""
echo "Verify routes now:"
rg -n 'fastify\.(get|post)\(' "$FILE" || true
echo ""
echo "DONE ✅"
