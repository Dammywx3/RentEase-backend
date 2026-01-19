#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
echo "ROOT=$ROOT"

mkdir -p scripts/.bak src/routes src/db

# -------------------------------------------------------------------
# (A) Ensure a PG pool module exists (route needs a client)
# -------------------------------------------------------------------
POOL_FILE="src/db/pool.ts"
if [ ! -f "$POOL_FILE" ]; then
  cat > "$POOL_FILE" <<'TS'
import { Pool } from "pg";

/**
 * Shared PG Pool
 * - Uses DATABASE_URL if present (Render/production friendly)
 * - Otherwise uses standard PG* env vars (PGHOST, PGUSER, etc.)
 */
export const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  host: process.env.PGHOST,
  port: process.env.PGPORT ? Number(process.env.PGPORT) : undefined,
  user: process.env.PGUSER,
  password: process.env.PGPASSWORD,
  database: process.env.PGDATABASE || process.env.DB_NAME,
  max: process.env.PGPOOL_MAX ? Number(process.env.PGPOOL_MAX) : 10,
  idleTimeoutMillis: process.env.PGPOOL_IDLE_MS ? Number(process.env.PGPOOL_IDLE_MS) : 30_000,
});
TS
  echo "✅ WROTE: $POOL_FILE"
else
  echo "ℹ️ Exists: $POOL_FILE (skipping)"
fi

# -------------------------------------------------------------------
# (B) Create purchases route plugin
# -------------------------------------------------------------------
PURCHASE_ROUTE_FILE="src/routes/purchases.routes.ts"
if [ -f "$PURCHASE_ROUTE_FILE" ]; then
  ts="$(date +%Y%m%d_%H%M%S)"
  cp "$PURCHASE_ROUTE_FILE" "scripts/.bak/purchases.routes.ts.bak.$ts"
  echo "✅ backup -> scripts/.bak/purchases.routes.ts.bak.$ts"
fi

cat > "$PURCHASE_ROUTE_FILE" <<'TS'
import type { FastifyInstance } from "fastify";
import { pool } from "../db/pool.js";
import { payPropertyPurchase } from "../services/purchase_payments.service.js";

/**
 * Purchases Routes (BUY FLOW)
 * POST /purchases/:purchaseId/pay
 *
 * Expects:
 *  - header: x-organization-id
 *  - body: { paymentMethod: "card"|"bank_transfer"|"wallet", amount?: number }
 */
export default async function purchasesRoutes(fastify: FastifyInstance) {
  fastify.post<{
    Params: { purchaseId: string };
    Body: { paymentMethod: "card" | "bank_transfer" | "wallet"; amount?: number };
  }>("/purchases/:purchaseId/pay", async (request, reply) => {
    const purchaseId = request.params.purchaseId;

    const orgHeader =
      (request.headers["x-organization-id"] as string | undefined) ||
      (request.headers["x-organizationid"] as string | undefined);

    if (!orgHeader) {
      return reply.code(400).send({
        ok: false,
        error: "MISSING_ORGANIZATION_ID",
        message: "Missing header: x-organization-id",
      });
    }

    const paymentMethod = request.body?.paymentMethod;
    const amount = request.body?.amount ?? null;

    const client = await pool.connect();
    try {
      await client.query("BEGIN");

      const result = await payPropertyPurchase(client, {
        organizationId: orgHeader,
        purchaseId,
        paymentMethod,
        amount: typeof amount === "number" ? amount : undefined,
      });

      await client.query("COMMIT");
      return reply.send({ ok: true, data: result });
    } catch (err) {
      try { await client.query("ROLLBACK"); } catch {}
      throw err;
    } finally {
      client.release();
    }
  });
}
TS

echo "✅ WROTE: $PURCHASE_ROUTE_FILE"

# -------------------------------------------------------------------
# (C) Auto-register purchasesRoutes under /v1
#     We try to find a v1 routes file by searching for prefix "/v1" or "/v1/me"
# -------------------------------------------------------------------
V1_FILE=""
V1_FILE="$(grep -RIl --exclude-dir=node_modules --exclude-dir=dist 'prefix: .*/v1' src 2>/dev/null | head -n 1 || true)"
if [ -z "$V1_FILE" ]; then
  V1_FILE="$(grep -RIl --exclude-dir=node_modules --exclude-dir=dist '/v1/me' src 2>/dev/null | head -n 1 || true)"
fi
if [ -z "$V1_FILE" ]; then
  V1_FILE="$(grep -RIl --exclude-dir=node_modules --exclude-dir=dist 'register\\(.*prefix:.*v1' src 2>/dev/null | head -n 1 || true)"
fi

if [ -z "$V1_FILE" ]; then
  echo ""
  echo "⚠️ Could not auto-find your v1 routes file to register purchasesRoutes."
  echo "➡️ Manually register it in your v1 router/plugin with:"
  echo "   import purchasesRoutes from './purchases.routes.js'"
  echo "   fastify.register(purchasesRoutes)"
  echo "   (or if v1 prefix is set elsewhere) fastify.register(purchasesRoutes)"
  echo ""
  echo "To locate your v1 file, run:"
  echo "  grep -RIn \"prefix:.*v1\" src | head"
  echo "  grep -RIn \"/v1/me\" src | head"
  exit 0
fi

echo "✅ Found v1 routes file: $V1_FILE"

# backup v1 file
ts="$(date +%Y%m%d_%H%M%S)"
cp "$V1_FILE" "scripts/.bak/$(basename "$V1_FILE").bak.$ts"
echo "✅ backup -> scripts/.bak/$(basename "$V1_FILE").bak.$ts"

# Add import if missing
if ! grep -q "purchases.routes" "$V1_FILE"; then
  # try to insert after other imports
  perl -0777 -i -pe 's/(^import .*;\n)/$1import purchasesRoutes from ".\/purchases.routes.js";\n/m' "$V1_FILE" \
    || echo "⚠️ import insert failed (you can add it manually)"
fi

# Add register line if missing
if ! grep -q "register(.*purchasesRoutes" "$V1_FILE"; then
  # Insert after first register(...) line, or near other route registrations
  perl -0777 -i -pe '
    if ($_ !~ /purchasesRoutes/) {
      s/(fastify\.register\([^\n]*\);\n)/$1fastify.register(purchasesRoutes);\n/s;
    }
  ' "$V1_FILE" || true
fi

# If still not registered, append at end of file before last closing brace
if ! grep -q "register(.*purchasesRoutes" "$V1_FILE"; then
  perl -0777 -i -pe 's/\n}\s*$/\n  fastify.register(purchasesRoutes);\n}\n/s' "$V1_FILE" || true
fi

echo "✅ PATCHED: registered purchasesRoutes inside $V1_FILE"

echo ""
echo "== DONE =="
echo "Next:"
echo "  1) Restart server: npm run dev"
echo "  2) Call:"
echo "     curl -sS -X POST \"$API/v1/purchases/$PURCHASE_ID/pay\" -H \"content-type: application/json\" -H \"authorization: Bearer \$TOKEN\" -H \"x-organization-id: \$ORG_ID\" -d '{\"paymentMethod\":\"card\",\"amount\":2000}' | jq"
