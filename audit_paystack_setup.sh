#!/usr/bin/env bash
set -euo pipefail

API="${API:-http://127.0.0.1:4000}"

echo "== RentEase Paystack Setup Audit =="
echo "API: $API"
echo ""

echo "1) Env:"
echo "   PAYSTACK_SECRET_KEY set? -> $( [[ -n "${PAYSTACK_SECRET_KEY:-}" ]] && echo YES || echo NO )"
echo ""

echo "2) Installed package:"
npm ls fastify-raw-body >/dev/null 2>&1 && echo "   fastify-raw-body: OK" || echo "   fastify-raw-body: MISSING"
echo ""

echo "3) Webhook routes in code:"
grep -RIn --exclude-dir=node_modules --exclude='*.bak*' "/webhooks/paystack" src || true
echo ""

echo "4) webhooksRoutes registered where?"
grep -n "webhooksRoutes" src/routes/index.ts || true
echo ""

echo "5) Quick runtime probe (expect 401 INVALID_SIGNATURE if verification is on):"
curl -sS -i -X POST "$API/webhooks/paystack" -H "Content-Type: application/json" -d '{"event":"ping","data":{}}' | sed -n '1,25p'
echo ""

echo "6) Typecheck:"
npm run typecheck 2>/dev/null || npx tsc -p tsconfig.json --noEmit
echo ""
echo "== DONE =="
