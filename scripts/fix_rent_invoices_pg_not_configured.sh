#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "🔧 Patching rent invoices to use pool.connect() (no app.pg)..."

# --- 1) routes: rent_invoices.ts ---
cat > "$ROOT/src/routes/rent_invoices.ts" <<'TS'
import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { pool } from "../config/database.js";
import { generateRentInvoiceForTenancy, getRentInvoices } from "../services/rent_invoices.service.js";

const InvoiceStatus = z.enum(["draft", "issued", "paid", "overdue", "void", "cancelled"]);

/**
 * IMPORTANT:
 * - We do NOT use app.pg (fastify-postgres). We use our Pool from config/database.ts
 * - We set DB session context so current_user_uuid() / current_organization_uuid() work for RLS + defaults.
 */
function getOrgId(req: any): string | null {
  const h = req.headers?.["x-organization-id"];
  if (typeof h === "string" && h.length) return h;
  // fallback if your jwt plugin stores org in user
  if (req.user?.org && typeof req.user.org === "string") return req.user.org;
  if (req.user?.organization_id && typeof req.user.organization_id === "string") return req.user.organization_id;
  return null;
}

function getUserId(req: any): string | null {
  // fastify-jwt typically puts "sub" in req.user
  if (req.user?.sub && typeof req.user.sub === "string") return req.user.sub;
  if (req.user?.id && typeof req.user.id === "string") return req.user.id;
  return null;
}

function getRole(req: any): string {
  if (req.user?.role && typeof req.user.role === "string") return req.user.role;
  return "tenant";
}

/**
 * Set as many common settings as possible (safe no-ops if your SQL functions don't use some of them).
 * This prevents "organization_id null" and makes RLS helpers work.
 */
async function setDbContext(client: any, req: any) {
  const orgId = getOrgId(req);
  const userId = getUserId(req);
  const role = getRole(req);

  if (!orgId) {
    const err: any = new Error("Missing x-organization-id header");
    err.code = "ORG_ID_MISSING";
    throw err;
  }
  if (!userId) {
    const err: any = new Error("Missing authenticated user id (req.user.sub)");
    err.code = "USER_ID_MISSING";
    throw err;
  }

  await client.query(
    `
    SELECT
      set_config('request.jwt.claim.sub', $1, true),
      set_config('request.jwt.claim.role', $2, true),
      set_config('request.header.x-organization-id', $3, true),
      set_config('app.current_user_uuid', $1, true),
      set_config('app.current_organization_uuid', $3, true);
    `,
    [userId, role, orgId]
  );

  return { orgId, userId, role };
}

export async function rentInvoicesRoutes(app: FastifyInstance) {
  // Generate a rent invoice for a given tenancy
  app.post("/v1/tenancies/:id/rent-invoices/generate", async (req, reply) => {
    const params = z.object({ id: z.string().uuid() }).parse((req as any).params);

    const body = z
      .object({
        periodStart: z.string(), // YYYY-MM-DD
        periodEnd: z.string(),   // YYYY-MM-DD
        dueDate: z.string(),     // YYYY-MM-DD

        subtotal: z.number().optional(),
        lateFeeAmount: z.number().nullable().optional(),
        currency: z.string().nullable().optional(),
        status: InvoiceStatus.nullable().optional(),
        notes: z.string().nullable().optional(),
      })
      .parse((req as any).body);

    const client = await pool.connect();
    try {
      await client.query("BEGIN");
      await setDbContext(client, req);

      const res = await generateRentInvoiceForTenancy(client, {
        tenancyId: params.id,
        periodStart: body.periodStart,
        periodEnd: body.periodEnd,
        dueDate: body.dueDate,
        subtotal: body.subtotal,
        lateFeeAmount: body.lateFeeAmount,
        currency: body.currency,
        status: body.status ?? undefined,
        notes: body.notes ?? undefined,
      });

      await client.query("COMMIT");
      return reply.send({ ok: true, reused: res.reused, data: res.row });
    } catch (err: any) {
      await client.query("ROLLBACK");
      return reply
        .code(500)
        .send({ ok: false, error: err?.code ?? "INTERNAL_ERROR", message: err?.message ?? String(err) });
    } finally {
      client.release();
    }
  });

  // List invoices (filters)
  app.get("/v1/rent-invoices", async (req, reply) => {
    const q = z
      .object({
        limit: z.coerce.number().min(1).max(200).default(20),
        offset: z.coerce.number().min(0).default(0),
        tenancyId: z.string().uuid().optional(),
        tenantId: z.string().uuid().optional(),
        propertyId: z.string().uuid().optional(),
        status: InvoiceStatus.optional(),
      })
      .parse((req as any).query);

    const client = await pool.connect();
    try {
      await setDbContext(client, req);

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
      return reply
        .code(500)
        .send({ ok: false, error: err?.code ?? "INTERNAL_ERROR", message: err?.message ?? String(err) });
    } finally {
      client.release();
    }
  });
}
TS

# --- 2) routes/index.ts: remove duplicate register lines for rentInvoicesRoutes ---
INDEX="$ROOT/src/routes/index.ts"
if [ -f "$INDEX" ]; then
  echo "🔧 Fixing duplicate rentInvoicesRoutes registration in src/routes/index.ts ..."
  # Keep import, but ensure only one app.register(rentInvoicesRoutes)
  # Remove any direct "await rentInvoicesRoutes(app);" if exists
  perl -0777 -i -pe 's/^\s*await\s+rentInvoicesRoutes\(app\);\s*\n//mg' "$INDEX"
  # Replace multiple occurrences with a single one
  perl -0777 -i -pe '
    my $count = () = $_ =~ /app\.register\(rentInvoicesRoutes\)/g;
    if ($count > 1) {
      $_ =~ s/app\.register\(rentInvoicesRoutes\);\s*\n//g;
      $_ =~ s/(export\s+async\s+function\s+registerRoutes\s*\(\s*app:\s*FastifyInstance\s*\)\s*\{\s*)/$1  await app.register(rentInvoicesRoutes);\n/;
    } elsif ($count == 0) {
      $_ =~ s/(export\s+async\s+function\s+registerRoutes\s*\(\s*app:\s*FastifyInstance\s*\)\s*\{\s*)/$1  await app.register(rentInvoicesRoutes);\n/;
    }
  ' "$INDEX"
fi

# --- 3) server.ts: ensure routes are registered only once ---
SERVER="$ROOT/src/server.ts"
if [ -f "$SERVER" ]; then
  echo "🔧 Fixing double route registration in src/server.ts ..."
  # remove the mistaken direct call if present
  perl -0777 -i -pe 's/\n\s*await\s+await\s+registerRoutes\(app\);\s*\n/\n/g' "$SERVER"
  perl -0777 -i -pe 's/\n\s*await\s+registerRoutes\(app\);\s*\n/\n/g' "$SERVER"
fi

echo "✅ Rent invoices PG fix applied."
echo "➡️  Restart dev server: npm run dev"
