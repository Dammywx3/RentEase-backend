#!/usr/bin/env bash
set -euo pipefail

FILE="src/routes/purchases.routes.ts"
if [[ ! -f "$FILE" ]]; then
  echo "❌ Not found: $FILE"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p scripts/.bak
cp "$FILE" "scripts/.bak/purchases.routes.ts.bak.$TS"
echo "✅ backup -> scripts/.bak/purchases.routes.ts.bak.$TS"

# 1) Delete the broken dangling generic post fragment, if present
# It starts at: fastify.post<{ ... }>  and is immediately followed by comment/GET route.
perl -0777 -i -pe 's/\n\s*fastify\.post<\{\s*[\s\S]*?\}\>\s*\n\s*\/\/ ------------------------------------------------------------\n\s*\/\/ GET \/purchases \(list\)\n\s*\/\/ ------------------------------------------------------------/\n\n  \/\/ ------------------------------------------------------------\n  \/\/ POST \/purchases\/:purchaseId\/pay\n  \/\/ ------------------------------------------------------------/m' "$FILE"

# 2) If we didn't replace (i.e., pattern didn't match), we still proceed and inject POST block
# right after function start if POST is missing.
if ! grep -q 'POST /purchases/:purchaseId/pay' "$FILE"; then
  echo "❌ Could not locate insertion point (function start). Aborting to avoid corrupting file."
  exit 1
fi

# 3) Inject the actual POST route block right after our marker comment line.
perl -0777 -i -pe 's/(\/\/ POST \/purchases\/:purchaseId\/pay\n\s*\/\/ ------------------------------------------------------------)\n/\1\n\n  fastify.post<{\n    Params: { purchaseId: string };\n    Body: { paymentMethod: \"card\" | \"bank_transfer\" | \"wallet\"; amount?: number };\n  }>(\"\/purchases\/:purchaseId\/pay\", async (request, reply) => {\n    const orgId = String(request.headers[\"x-organization-id\"] || \"\");\n    if (!orgId) {\n      return reply.code(400).send({ ok: false, error: \"ORG_REQUIRED\", message: \"x-organization-id required\" });\n    }\n\n    const { purchaseId } = request.params;\n    const paymentMethod = request.body?.paymentMethod;\n    const amount = request.body?.amount;\n\n    if (!paymentMethod) {\n      return reply.code(400).send({ ok: false, error: \"PAYMENT_METHOD_REQUIRED\", message: \"paymentMethod required\" });\n    }\n\n    const client = await fastify.pg.connect();\n    try {\n      const result = await payPropertyPurchase(client, {\n        organizationId: orgId,\n        purchaseId,\n        paymentMethod,\n        amount: typeof amount === \"number\" ? amount : null,\n      });\n\n      return reply.send({ ok: true, data: result });\n    } finally {\n      client.release();\n    }\n  });\n\n/m' "$FILE"

# 4) Quick sanity check: ensure the post route now exists
if ! grep -q 'fastify.post<{' "$FILE" || ! grep -q '"/purchases/:purchaseId/pay"' "$FILE"; then
  echo "❌ Patch failed: POST route not found after patch."
  exit 1
fi

echo "✅ FIXED: POST /purchases/:purchaseId/pay restored in $FILE"
echo "➡️ Next: restart server: npm run dev"
