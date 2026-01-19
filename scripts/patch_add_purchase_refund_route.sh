#!/usr/bin/env bash
set -euo pipefail

FILE="src/routes/purchases.routes.ts"
if [ ! -f "$FILE" ]; then
  echo "❌ Not found: $FILE"
  exit 1
fi

mkdir -p scripts/.bak
cp "$FILE" "scripts/.bak/purchases.routes.ts.bak.$(date +%Y%m%d_%H%M%S)"

# Prevent duplicate insertion
if grep -q '"/purchases/:purchaseId/refund"' "$FILE"; then
  echo "ℹ️ Refund route already exists (skipping)."
  exit 0
fi

# Ensure import exists (you already have it; keep safe)
if ! grep -q 'refundPropertyPurchase' "$FILE"; then
  perl -0777 -i -pe 's/(import .*?;\s*\n)/$1import { refundPropertyPurchase } from "..\/services\/purchase_refunds.service.js";\n/s' "$FILE"
fi

# Insert refund route right BEFORE the pay route (best spot)
perl -0777 -i -pe '
my $route = qq{

  // ------------------------------------------------------------
  // POST /purchases/:purchaseId/refund
  // ------------------------------------------------------------
  fastify.post<{
    Params: { purchaseId: string };
    Body: { refundMethod: "card" | "bank_transfer" | "wallet"; amount?: number };
  }>("/purchases/:purchaseId/refund", async (request, reply) => {
    const orgId = String(request.headers["x-organization-id"] || "");
    if (!orgId) {
      return reply.code(400).send({ ok: false, error: "ORG_REQUIRED", message: "x-organization-id required" });
    }

    const { purchaseId } = request.params;
    const refundMethod = request.body?.refundMethod;
    const amount = request.body?.amount;

    if (!refundMethod) {
      return reply.code(400).send({ ok: false, error: "REFUND_METHOD_REQUIRED", message: "refundMethod is required" });
    }

    const client = await fastify.pg.connect();
    try {
      const result = await refundPropertyPurchase(client, {
        organizationId: orgId,
        purchaseId,
        refundMethod,
        amount,
      });

      return reply.send({ ok: true, data: result });
    } catch (err: any) {
      const msg = err?.message || "Refund failed";
      const code = err?.code || "REFUND_FAILED";
      return reply.code(400).send({ ok: false, error: code, message: msg });
    } finally {
      client.release();
    }
  });

};

if ($_ =~ /fastify\.post<\{\s*Params:\s*\{\s*purchaseId:\s*string\s*\}.*?\}>\s*\(\"\/purchases\/:purchaseId\/pay\"/s) {
  s/(fastify\.post<\{\s*Params:\s*\{\s*purchaseId:\s*string\s*\}.*?\}>\s*\(\"\/purchases\/:purchaseId\/pay\")/$route\n$1/s;
} else {
  # fallback: insert after function open
  s/(export default async function purchasesRoutes\(fastify: FastifyInstance\)\s*\{\s*)/$1$route\n/s;
}
' "$FILE"

# Verify route exists
if ! grep -q '"/purchases/:purchaseId/refund"' "$FILE"; then
  echo "❌ Patch failed: refund route still missing."
  exit 1
fi

echo "✅ PATCHED: added POST /purchases/:purchaseId/refund in $FILE"
echo "➡️ Restart server: npm run dev"
