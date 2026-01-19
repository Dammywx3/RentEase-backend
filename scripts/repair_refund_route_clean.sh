#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROUTES="$ROOT/src/routes/purchases.routes.ts"

[ -f "$ROUTES" ] || { echo "❌ Not found: $ROUTES"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$ROOT/scripts/.bak"
cp "$ROUTES" "$ROOT/scripts/.bak/purchases.routes.ts.bak.$TS"
echo "✅ backup -> scripts/.bak/purchases.routes.ts.bak.$TS"

export ROUTES

python3 - <<'PY'
from pathlib import Path
import os, re

routes = Path(os.environ["ROUTES"])
t = routes.read_text(encoding="utf-8")

# 1) Ensure Body type includes audit fields (reason/refundPaymentId/refundedBy)
t = re.sub(
    r'Body:\s*\{\s*refundMethod:\s*"card"\s*\|\s*"bank_transfer"\s*\|\s*"wallet";\s*amount\?:\s*number;\s*\}',
    'Body: { refundMethod: "card" | "bank_transfer" | "wallet"; amount?: number; reason?: string; refundPaymentId?: string; refundedBy?: string }',
    t
)

# 2) Replace the entire refund route handler block with a clean one.
pat = r"""
fastify\.post<\{\s*
\s*Params:\s*\{\s*purchaseId:\s*string\s*\}\s*;\s*
\s*Body:\s*\{[\s\S]*?\}\s*;\s*
\}>\(\s*["']\/purchases\/:purchaseId\/refund["']\s*,\s*async\s*\(request,\s*reply\)\s*=>\s*\{
[\s\S]*?
\}\s*\)\s*;
"""
replacement = r"""fastify.post<{
    Params: { purchaseId: string };
    Body: {
      refundMethod: "card" | "bank_transfer" | "wallet";
      amount?: number;
      reason?: string;
      refundPaymentId?: string;
      refundedBy?: string;
    };
  }>("/purchases/:purchaseId/refund", async (request, reply) => {
    const orgId = String(request.headers["x-organization-id"] || "");
    if (!orgId) {
      return reply
        .code(400)
        .send({ ok: false, error: "ORG_REQUIRED", message: "x-organization-id required" });
    }

    const { purchaseId } = request.params;

    const refundMethod = request.body?.refundMethod ?? null;
    const amount = request.body?.amount;

    // optional audit fields
    const reason = (request.body as any)?.reason ?? null;
    const refundPaymentId = (request.body as any)?.refundPaymentId ?? null;

    // IMPORTANT: auth may not attach user; fallback to body.refundedBy when testing
    const refundedByUserId =
      (request as any).user?.id ??
      (request as any).user?.sub ??
      (request.body as any)?.refundedBy ??
      null;

    if (!refundMethod) {
      return reply.code(400).send({
        ok: false,
        error: "REFUND_METHOD_REQUIRED",
        message: "refundMethod is required",
      });
    }

    const client = await fastify.pg.connect();
    try {
      const result = await refundPropertyPurchase(client, {
        organizationId: orgId,
        purchaseId,
        amount: typeof amount === "number" ? amount : undefined,

        // ✅ correct mapping
        refundMethod,
        reason,
        refundPaymentId,
        refundedBy: refundedByUserId,
      });

      return reply.send({ ok: true, data: result });
    } catch (err: any) {
      return reply.code(400).send({
        ok: false,
        error: err?.code || "REFUND_FAILED",
        message: err?.message || "Refund failed",
      });
    } finally {
      client.release();
    }
  });
"""

t2, n = re.subn(pat, replacement, t, count=1, flags=re.VERBOSE)
if n != 1:
    raise SystemExit("❌ Could not locate the refund route block to replace (pattern mismatch).")

routes.write_text(t2, encoding="utf-8")
print("✅ refund route fully replaced (duplicates removed)")
PY

echo "🔎 Typecheck..."
npx -y tsc -p "$ROOT/tsconfig.json" --noEmit
echo "✅ Typecheck passed"
