#!/usr/bin/env bash
set -u

echo "== Fix rent invoices: PG + auth + RLS ctx =="

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

# --- Detect which custom GUC keys your DB functions expect ---
# We parse current_setting('...') inside current_organization_uuid() and current_user_uuid()
DB_NAME="${DB_NAME:-rentease}"

ORG_DEF="$(psql -d "$DB_NAME" -Atc "select pg_get_functiondef('public.current_organization_uuid()'::regprocedure);" 2>/dev/null || true)"
USR_DEF="$(psql -d "$DB_NAME" -Atc "select pg_get_functiondef('public.current_user_uuid()'::regprocedure);" 2>/dev/null || true)"

# Extract first current_setting('KEY'
ORG_GUC="$(printf "%s" "$ORG_DEF" | grep -oE "current_setting\('([^']+)'" | head -1 | sed -E "s/current_setting\('([^']+)'/\1/")"
USR_GUC="$(printf "%s" "$USR_DEF" | grep -oE "current_setting\('([^']+)'" | head -1 | sed -E "s/current_setting\('([^']+)'/\1/")"

# Fallbacks if parsing fails
# (These are common safe names we used in earlier fixes; underscores only)
if [ -z "${ORG_GUC:-}" ]; then ORG_GUC="app.current_organization_id"; fi
if [ -z "${USR_GUC:-}" ]; then USR_GUC="app.current_user_id"; fi

echo "DB_NAME=$DB_NAME"
echo "ORG_GUC=$ORG_GUC"
echo "USR_GUC=$USR_GUC"

# --- Overwrite rent invoices routes to use pool + jwtVerify + set_config ---
cat > src/routes/rent_invoices.ts <<TS
import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { pool } from "../config/database.js";
import { generateRentInvoiceForTenancy, getRentInvoices } from "../services/rent_invoices.service.js";

const InvoiceStatus = z.enum(["draft","issued","paid","overdue","void","cancelled"]);

function getOrgId(req: any): string | null {
  const h = req.headers?.["x-organization-id"] ?? req.headers?.["X-Organization-Id"];
  if (typeof h === "string" && h.length > 0) return h;
  const u = req.user as any;
  if (u?.org && typeof u.org === "string") return u.org;
  return null;
}

function getUserId(req: any): string | null {
  const u = req.user as any;
  if (u?.sub && typeof u.sub === "string") return u.sub;
  if (u?.id && typeof u.id === "string") return u.id;
  return null;
}

async function setRlsContext(client: any, orgId: string, userId: string) {
  // IMPORTANT: GUC names cannot include hyphens. We use whatever your DB funcs expect (auto-detected),
  // but they MUST be valid names. If your DB functions use a bad key, fix the SQL functions.
  await client.query("select set_config(\$1, \$2, true)", ["${ORG_GUC}", orgId]);
  await client.query("select set_config(\$1, \$2, true)", ["${USR_GUC}", userId]);
}

export async function rentInvoicesRoutes(app: FastifyInstance) {
  // Generate invoice for tenancy
  app.post("/v1/tenancies/:id/rent-invoices/generate", async (req, reply) => {
    // ensure req.user exists
    if (typeof (req as any).jwtVerify === "function") {
      await (req as any).jwtVerify();
    }

    const params = z.object({ id: z.string().uuid() }).parse((req as any).params);
    const body = z.object({
      periodStart: z.string(), // YYYY-MM-DD
      periodEnd: z.string(),   // YYYY-MM-DD
      dueDate: z.string(),     // YYYY-MM-DD
      subtotal: z.number().optional(),
      lateFeeAmount: z.number().nullable().optional(),
      currency: z.string().nullable().optional(),
      status: InvoiceStatus.nullable().optional(),
      notes: z.string().nullable().optional(),
    }).parse((req as any).body);

    const orgId = getOrgId(req);
    const userId = getUserId(req);
    if (!userId) return reply.code(401).send({ ok: false, error: "USER_ID_MISSING", message: "Missing authenticated user id (req.user.sub)" });
    if (!orgId) return reply.code(400).send({ ok: false, error: "ORG_CONTEXT_MISSING", message: "Missing x-organization-id header (org context required for RLS)" });

    const client = await pool.connect();
    try {
      await client.query("BEGIN");
      await setRlsContext(client, orgId, userId);

      const res = await generateRentInvoiceForTenancy(client, {
        tenancyId: params.id,
        periodStart: body.periodStart,
        periodEnd: body.periodEnd,
        dueDate: body.dueDate,
        subtotal: body.subtotal,
        lateFeeAmount: body.lateFeeAmount,
        currency: body.currency,
        status: body.status,
        notes: body.notes,
      });

      await client.query("COMMIT");
      return reply.send({ ok: true, reused: res.reused, data: res.row });
    } catch (err: any) {
      await client.query("ROLLBACK");
      return reply.code(500).send({ ok: false, error: err?.code ?? "INTERNAL_ERROR", message: err?.message ?? String(err) });
    } finally {
      client.release();
    }
  });

  // List invoices
  app.get("/v1/rent-invoices", async (req, reply) => {
    if (typeof (req as any).jwtVerify === "function") {
      await (req as any).jwtVerify();
    }

    const q = z.object({
      limit: z.coerce.number().min(1).max(200).default(20),
      offset: z.coerce.number().min(0).default(0),
      tenancyId: z.string().uuid().optional(),
      tenantId: z.string().uuid().optional(),
      propertyId: z.string().uuid().optional(),
      status: InvoiceStatus.optional(),
    }).parse((req as any).query);

    const orgId = getOrgId(req);
    const userId = getUserId(req);
    if (!userId) return reply.code(401).send({ ok: false, error: "USER_ID_MISSING", message: "Missing authenticated user id (req.user.sub)" });
    if (!orgId) return reply.code(400).send({ ok: false, error: "ORG_CONTEXT_MISSING", message: "Missing x-organization-id header (org context required for RLS)" });

    const client = await pool.connect();
    try {
      await setRlsContext(client, orgId, userId);

      const data = await getRentInvoices(client, {
        limit: q.limit,
        offset: q.offset,
        tenancyId: q.tenancyId,
        tenantId: q.tenantId,
        propertyId: q.propertyId,
        status: q.status,
      });

      return reply.send({ ok: true, data, paging: { limit: q.limit, offset: q.offset } });
    } catch (err: any) {
      return reply.code(500).send({ ok: false, error: err?.code ?? "INTERNAL_ERROR", message: err?.message ?? String(err) });
    } finally {
      client.release();
    }
  });
}
TS

echo "✅ Patched: src/routes/rent_invoices.ts (pool + jwtVerify + RLS ctx)"
echo "➡️ Restart server: npm run dev"
