#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(pwd)"
mkdir -p scripts

ts() { date +"%Y%m%d_%H%M%S"; }
backup() {
  local f="$1"
  if [[ -f "$f" ]]; then
    cp "$f" "$f.bak.$(ts)"
  fi
}

echo "�� Applying Start Tenancy endpoint (PATCH /v1/tenancies/:id/start) ..."

# --- backups ---
backup "src/schemas/tenancies.schema.ts"
backup "src/repos/tenancies.repo.ts"
backup "src/services/tenancies.service.ts"
backup "src/routes/tenancies.ts"

# ============================================================
# 1) Schemas: src/schemas/tenancies.schema.ts
#    - Fixes duplicate exported types
#    - Adds Start Tenancy schemas/types
# ============================================================
cat > src/schemas/tenancies.schema.ts <<'EOF'
import { z } from "zod";

export const tenancyStatusSchema = z.enum(["active", "ended", "terminated", "pending_start"]);

const dateOnly = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Expected YYYY-MM-DD");

/** --- CREATE TENANCY --- */
export const createTenancyBodySchema = z.object({
  tenantId: z.string().uuid(),
  propertyId: z.string().uuid(),
  listingId: z.string().uuid().nullable().optional(),

  rentAmount: z.number().positive(),
  securityDeposit: z.number().nonnegative().nullable().optional(),

  startDate: dateOnly,
  nextDueDate: dateOnly,

  paymentCycle: z.string().optional(),
  status: tenancyStatusSchema.optional(),

  terminationReason: z.string().max(5000).nullable().optional(),
});

export type CreateTenancyBody = z.infer<typeof createTenancyBodySchema>;

/** --- LIST TENANCIES --- */
export const listTenanciesQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(10),
  offset: z.coerce.number().int().min(0).default(0),

  tenantId: z.string().uuid().optional(),
  propertyId: z.string().uuid().optional(),
  listingId: z.string().uuid().optional(),
  status: tenancyStatusSchema.optional(),
});

export type ListTenanciesQuery = z.infer<typeof listTenanciesQuerySchema>;

/** --- END TENANCY --- */
export const endTenancyParamsSchema = z.object({
  id: z.string().uuid(),
});

export const endTenancyBodySchema = z.object({
  status: z.enum(["ended", "terminated"]).default("ended"),
  endDate: dateOnly.optional(), // if omitted server can default (repo/service can set)
  terminationReason: z.string().max(5000).nullable().optional(),
});

export type EndTenancyParams = z.infer<typeof endTenancyParamsSchema>;
export type EndTenancyBody = z.infer<typeof endTenancyBodySchema>;

/** --- START TENANCY (NEW) --- */
export const startTenancyParamsSchema = z.object({
  id: z.string().uuid(),
});

export const startTenancyBodySchema = z.object({
  startDate: dateOnly.optional(), // optional override; otherwise keep existing start_date
});

export type StartTenancyParams = z.infer<typeof startTenancyParamsSchema>;
export type StartTenancyBody = z.infer<typeof startTenancyBodySchema>;
EOF

# ============================================================
# 2) Repo: src/repos/tenancies.repo.ts
#    - Adds startTenancyById() (idempotent)
#    - Keeps idempotent create logic + list
#    - Includes endTenancyById() (idempotent) so routes/services can use it
# ============================================================
cat > src/repos/tenancies.repo.ts <<'EOF'
import type { PoolClient } from "pg";

export type TenancyStatus = "active" | "ended" | "terminated" | "pending_start";

export type TenancyRow = {
  id: string;

  tenant_id: string;
  property_id: string;
  listing_id: string | null;

  rent_amount: string;
  security_deposit: string | null;
  payment_cycle: string | null;

  start_date: string; // YYYY-MM-DD
  end_date: string | null; // YYYY-MM-DD or null
  next_due_date: string; // YYYY-MM-DD

  notice_period_days: number | null;
  status: TenancyStatus | null;

  termination_reason: string | null;
  late_fee_percentage: string | null;
  grace_period_days: number | null;

  created_at: string;
  updated_at: string;
  deleted_at: string | null;

  version: number | null;
};

export type InsertTenancyArgs = {
  tenant_id: string;
  property_id: string;
  listing_id?: string | null;

  rent_amount: number;
  security_deposit?: number | null;

  start_date: string; // YYYY-MM-DD
  next_due_date: string; // YYYY-MM-DD

  payment_cycle?: string | null;
  status?: TenancyStatus | null;

  termination_reason?: string | null;
};

// Reusable SELECT list (casts DATE -> TEXT so API returns "YYYY-MM-DD")
const TENANCY_SELECT = `
  t.id,
  t.tenant_id,
  t.property_id,
  t.listing_id,
  t.rent_amount,
  t.security_deposit,
  t.payment_cycle,
  t.start_date::text    AS start_date,
  t.end_date::text      AS end_date,
  t.next_due_date::text AS next_due_date,
  t.notice_period_days,
  t.status,
  t.termination_reason,
  t.late_fee_percentage,
  t.grace_period_days,
  t.created_at,
  t.updated_at,
  t.deleted_at,
  t.version
`;

const OPEN_STATUSES: TenancyStatus[] = ["active", "pending_start"];

export async function findTenancyById(client: PoolClient, id: string): Promise<TenancyRow | null> {
  const { rows } = await client.query<TenancyRow>(
    `
    SELECT ${TENANCY_SELECT}
    FROM public.tenancies t
    WHERE t.id = $1
    LIMIT 1;
    `,
    [id]
  );
  return rows[0] ?? null;
}

export async function findOpenTenancyByTenantProperty(
  client: PoolClient,
  tenantId: string,
  propertyId: string
): Promise<TenancyRow | null> {
  const { rows } = await client.query<TenancyRow>(
    `
    SELECT ${TENANCY_SELECT}
    FROM public.tenancies t
    WHERE t.tenant_id = $1
      AND t.property_id = $2
      AND t.deleted_at IS NULL
      AND t.status = ANY($3::tenancy_status[])
    ORDER BY t.created_at DESC
    LIMIT 1;
    `,
    [tenantId, propertyId, OPEN_STATUSES]
  );
  return rows[0] ?? null;
}

export async function patchOpenTenancyMissingFields(
  client: PoolClient,
  tenancyId: string,
  patch: {
    listing_id?: string | null;
    security_deposit?: number | null;
    termination_reason?: string | null;
  }
): Promise<{ row: TenancyRow; patched: boolean }> {
  const { rows } = await client.query<TenancyRow & { patched: boolean }>(
    `
    WITH prev AS (
      SELECT
        t.id,
        t.listing_id,
        t.security_deposit,
        t.termination_reason
      FROM public.tenancies t
      WHERE t.id = $1
      FOR UPDATE
    ),
    upd AS (
      UPDATE public.tenancies t
      SET
        listing_id = COALESCE(prev.listing_id, $2::uuid),
        security_deposit = COALESCE(prev.security_deposit, $3::numeric),
        termination_reason = COALESCE(prev.termination_reason, $4::text),
        updated_at = CASE
          WHEN
            (prev.listing_id IS NULL AND $2::uuid IS NOT NULL)
            OR (prev.security_deposit IS NULL AND $3::numeric IS NOT NULL)
            OR (prev.termination_reason IS NULL AND $4::text IS NOT NULL)
          THEN NOW()
          ELSE t.updated_at
        END
      FROM prev
      WHERE t.id = prev.id
      RETURNING
        ${TENANCY_SELECT},
        (
          (prev.listing_id IS NULL AND $2::uuid IS NOT NULL)
          OR (prev.security_deposit IS NULL AND $3::numeric IS NOT NULL)
          OR (prev.termination_reason IS NULL AND $4::text IS NOT NULL)
        ) AS patched
    )
    SELECT * FROM upd;
    `,
    [tenancyId, patch.listing_id ?? null, patch.security_deposit ?? null, patch.termination_reason ?? null]
  );

  const row = rows[0]!;
  const patched = (row as any).patched === true;
  delete (row as any).patched;

  return { row, patched };
}

export async function insertTenancy(client: PoolClient, data: InsertTenancyArgs): Promise<TenancyRow> {
  const { rows } = await client.query<TenancyRow>(
    `
    INSERT INTO public.tenancies (
      tenant_id,
      property_id,
      listing_id,
      rent_amount,
      security_deposit,
      start_date,
      next_due_date,
      payment_cycle,
      status,
      termination_reason
    )
    VALUES (
      $1, $2, $3,
      $4::numeric,
      $5::numeric,
      $6::date,
      $7::date,
      COALESCE($8::payment_cycle, 'monthly'::payment_cycle),
      COALESCE($9::tenancy_status, 'pending_start'::tenancy_status),
      $10
    )
    RETURNING ${TENANCY_SELECT};
    `,
    [
      data.tenant_id,
      data.property_id,
      data.listing_id ?? null,
      data.rent_amount,
      data.security_deposit ?? null,
      data.start_date,
      data.next_due_date,
      data.payment_cycle ?? null,
      data.status ?? null,
      data.termination_reason ?? null,
    ]
  );

  return rows[0]!;
}

export async function createTenancyIdempotent(
  client: PoolClient,
  data: InsertTenancyArgs
): Promise<{ row: TenancyRow; reused: boolean; patched: boolean }> {
  // 1) Fast path: open tenancy exists → patch missing fields only
  const existing = await findOpenTenancyByTenantProperty(client, data.tenant_id, data.property_id);
  if (existing) {
    const patchedRes = await patchOpenTenancyMissingFields(client, existing.id, {
      listing_id: data.listing_id ?? null,
      security_deposit: data.security_deposit ?? null,
      termination_reason: data.termination_reason ?? null,
    });
    return { row: patchedRes.row, reused: true, patched: patchedRes.patched };
  }

  // 2) No open tenancy → insert
  try {
    const row = await insertTenancy(client, data);
    return { row, reused: false, patched: false };
  } catch (err: any) {
    // 3) Race-safe: another request inserted first (partial unique index violation)
    if (err?.code === "23505") {
      const again = await findOpenTenancyByTenantProperty(client, data.tenant_id, data.property_id);
      if (again) {
        const patchedRes = await patchOpenTenancyMissingFields(client, again.id, {
          listing_id: data.listing_id ?? null,
          security_deposit: data.security_deposit ?? null,
          termination_reason: data.termination_reason ?? null,
        });
        return { row: patchedRes.row, reused: true, patched: patchedRes.patched };
      }
    }
    throw err;
  }
}

/**
 * END tenancy (idempotent)
 * - If already ended/terminated with same values -> changed=false
 * - If open (active/pending_start) -> updates -> changed=true
 */
export async function endTenancyById(
  client: PoolClient,
  id: string,
  input: {
    status: "ended" | "terminated";
    end_date?: string | null; // YYYY-MM-DD
    termination_reason?: string | null;
  }
): Promise<{ row: TenancyRow; changed: boolean }> {
  const { rows } = await client.query<TenancyRow & { changed: boolean }>(
    `
    WITH prev AS (
      SELECT
        t.id,
        t.status,
        t.end_date,
        t.termination_reason
      FROM public.tenancies t
      WHERE t.id = $1
      FOR UPDATE
    ),
    upd AS (
      UPDATE public.tenancies t
      SET
        status = CASE
          WHEN prev.status = ANY($2::tenancy_status[]) THEN $3::tenancy_status
          ELSE t.status
        END,
        end_date = CASE
          WHEN prev.status = ANY($2::tenancy_status[]) THEN COALESCE($4::date, CURRENT_DATE)
          ELSE t.end_date
        END,
        termination_reason = CASE
          WHEN prev.status = ANY($2::tenancy_status[]) THEN COALESCE($5::text, t.termination_reason)
          ELSE t.termination_reason
        END,
        updated_at = CASE
          WHEN prev.status = ANY($2::tenancy_status[]) THEN NOW()
          ELSE t.updated_at
        END
      FROM prev
      WHERE t.id = prev.id
      RETURNING
        ${TENANCY_SELECT},
        (prev.status = ANY($2::tenancy_status[])) AS changed
    )
    SELECT * FROM upd;
    `,
    [
      id,
      ["active", "pending_start"], // open statuses
      input.status,
      input.end_date ?? null,
      input.termination_reason ?? null,
    ]
  );

  const row = rows[0];
  if (!row) {
    // not found
    throw Object.assign(new Error("Tenancy not found"), { code: "TENANCY_NOT_FOUND" });
  }

  const changed = (row as any).changed === true;
  delete (row as any).changed;

  // If already ended/terminated, keep changed=false and return row
  return { row, changed };
}

/**
 * START tenancy (NEW, idempotent)
 * - Only transitions pending_start -> active
 * - If already active -> changed=false
 * - If ended/terminated -> changed=false (no-op) and returns row
 */
export async function startTenancyById(
  client: PoolClient,
  id: string,
  input: { start_date?: string | null }
): Promise<{ row: TenancyRow; changed: boolean }> {
  const { rows } = await client.query<TenancyRow & { changed: boolean }>(
    `
    WITH prev AS (
      SELECT
        t.id,
        t.status,
        t.start_date
      FROM public.tenancies t
      WHERE t.id = $1
      FOR UPDATE
    ),
    upd AS (
      UPDATE public.tenancies t
      SET
        status = CASE
          WHEN prev.status = 'pending_start'::tenancy_status THEN 'active'::tenancy_status
          ELSE t.status
        END,
        start_date = CASE
          WHEN prev.status = 'pending_start'::tenancy_status THEN COALESCE($2::date, t.start_date)
          ELSE t.start_date
        END,
        updated_at = CASE
          WHEN prev.status = 'pending_start'::tenancy_status THEN NOW()
          ELSE t.updated_at
        END
      FROM prev
      WHERE t.id = prev.id
      RETURNING
        ${TENANCY_SELECT},
        (prev.status = 'pending_start'::tenancy_status) AS changed
    )
    SELECT * FROM upd;
    `,
    [id, input.start_date ?? null]
  );

  const row = rows[0];
  if (!row) {
    throw Object.assign(new Error("Tenancy not found"), { code: "TENANCY_NOT_FOUND" });
  }

  const changed = (row as any).changed === true;
  delete (row as any).changed;

  return { row, changed };
}

export async function listTenancies(
  client: PoolClient,
  args: {
    limit: number;
    offset: number;
    tenant_id?: string;
    property_id?: string;
    listing_id?: string;
    status?: TenancyStatus;
  }
): Promise<TenancyRow[]> {
  const where: string[] = ["t.deleted_at IS NULL"];
  const params: any[] = [];
  let i = 1;

  if (args.tenant_id) {
    where.push(`t.tenant_id = $${i++}`);
    params.push(args.tenant_id);
  }
  if (args.property_id) {
    where.push(`t.property_id = $${i++}`);
    params.push(args.property_id);
  }
  if (args.listing_id) {
    where.push(`t.listing_id = $${i++}`);
    params.push(args.listing_id);
  }
  if (args.status) {
    where.push(`t.status = $${i++}::tenancy_status`);
    params.push(args.status);
  }

  params.push(args.limit);
  const limitIdx = i++;
  params.push(args.offset);
  const offsetIdx = i++;

  const { rows } = await client.query<TenancyRow>(
    `
    SELECT ${TENANCY_SELECT}
    FROM public.tenancies t
    WHERE ${where.join(" AND ")}
    ORDER BY t.created_at DESC
    LIMIT $${limitIdx} OFFSET $${offsetIdx};
    `,
    params
  );

  return rows;
}
EOF

# ============================================================
# 3) Service: src/services/tenancies.service.ts
#    - Adds startTenancy()
#    - Includes endTenancy() for completeness
# ============================================================
cat > src/services/tenancies.service.ts <<'EOF'
import type { PoolClient } from "pg";
import {
  createTenancyIdempotent,
  endTenancyById,
  listTenancies,
  startTenancyById,
  type TenancyStatus,
  type TenancyRow,
} from "../repos/tenancies.repo.js";

export async function createTenancy(
  client: PoolClient,
  input: {
    tenantId: string;
    propertyId: string;
    listingId?: string | null;

    rentAmount: number;
    securityDeposit?: number | null;

    startDate: string;
    nextDueDate: string;

    paymentCycle?: string | null;
    status?: TenancyStatus | null;

    terminationReason?: string | null;
  }
): Promise<{ row: TenancyRow; reused: boolean; patched: boolean }> {
  return createTenancyIdempotent(client, {
    tenant_id: input.tenantId,
    property_id: input.propertyId,
    listing_id: input.listingId ?? null,
    rent_amount: input.rentAmount,
    security_deposit: input.securityDeposit ?? null,
    start_date: input.startDate,
    next_due_date: input.nextDueDate,
    payment_cycle: input.paymentCycle ?? null,
    status: input.status ?? null,
    termination_reason: input.terminationReason ?? null,
  });
}

export async function getTenancies(
  client: PoolClient,
  args: {
    limit: number;
    offset: number;
    tenantId?: string;
    propertyId?: string;
    listingId?: string;
    status?: TenancyStatus;
  }
): Promise<TenancyRow[]> {
  return listTenancies(client, {
    limit: args.limit,
    offset: args.offset,
    tenant_id: args.tenantId,
    property_id: args.propertyId,
    listing_id: args.listingId,
    status: args.status,
  });
}

export async function endTenancy(
  client: PoolClient,
  input: {
    id: string;
    status: "ended" | "terminated";
    endDate?: string | null;
    terminationReason?: string | null;
  }
): Promise<{ row: TenancyRow; changed: boolean }> {
  return endTenancyById(client, input.id, {
    status: input.status,
    end_date: input.endDate ?? null,
    termination_reason: input.terminationReason ?? null,
  });
}

/** START TENANCY (NEW) */
export async function startTenancy(
  client: PoolClient,
  input: {
    id: string;
    startDate?: string | null;
  }
): Promise<{ row: TenancyRow; changed: boolean }> {
  return startTenancyById(client, input.id, {
    start_date: input.startDate ?? null,
  });
}
EOF

# ============================================================
# 4) Routes: src/routes/tenancies.ts
#    - Adds PATCH /v1/tenancies/:id/start
#    - Keeps GET/POST and PATCH /end
# ============================================================
cat > src/routes/tenancies.ts <<'EOF'
// src/routes/tenancies.ts
import type { FastifyInstance, FastifyRequest } from "fastify";

import { withRlsTransaction } from "../db.js";
import {
  createTenancyBodySchema,
  listTenanciesQuerySchema,
  endTenancyParamsSchema,
  endTenancyBodySchema,
  startTenancyParamsSchema,
  startTenancyBodySchema,
  type CreateTenancyBody,
  type ListTenanciesQuery,
  type EndTenancyBody,
  type EndTenancyParams,
  type StartTenancyBody,
  type StartTenancyParams,
} from "../schemas/tenancies.schema.js";
import { createTenancy, endTenancy, getTenancies, startTenancy } from "../services/tenancies.service.js";

function getRlsCtx(req: any): { userId: string; organizationId: string } {
  const rls = req?.rls;
  if (rls?.userId && rls?.organizationId) {
    return { userId: String(rls.userId), organizationId: String(rls.organizationId) };
  }

  const user = req?.user;

  const userId =
    user?.id ??
    user?.userId ??
    user?.sub ??
    req?.auth?.userId ??
    req?.auth?.sub;

  const hdr =
    req?.headers?.["x-organization-id"] ??
    req?.headers?.["x-org-id"] ??
    req?.headers?.["x-organizationid"];

  const userOrg =
    user?.organization_id ??
    user?.organizationId ??
    user?.org_id ??
    user?.orgId;

  const organizationId = hdr ?? userOrg;

  if (!userId || !organizationId) {
    throw new Error(
      `Missing RLS ctx. userId=${String(userId ?? "")} organizationId=${String(organizationId ?? "")}. ` +
        `Pass header x-organization-id OR ensure auth sets req.rls.`
    );
  }

  return { userId: String(userId), organizationId: String(organizationId) };
}

export async function tenancyRoutes(app: FastifyInstance) {
  app.get(
    "/v1/tenancies",
    { preHandler: [app.authenticate] },
    async (req: FastifyRequest<{ Querystring: ListTenanciesQuery }>) => {
      const q = listTenanciesQuerySchema.parse(req.query ?? {});
      const ctx = getRlsCtx(req);

      const data = await withRlsTransaction(ctx, (client) =>
        getTenancies(client, {
          limit: q.limit,
          offset: q.offset,
          tenantId: q.tenantId,
          propertyId: q.propertyId,
          listingId: q.listingId,
          status: q.status as any,
        })
      );

      return { ok: true, data, paging: { limit: q.limit, offset: q.offset } };
    }
  );

  app.post(
    "/v1/tenancies",
    { preHandler: [app.authenticate] },
    async (req: FastifyRequest<{ Body: CreateTenancyBody }>) => {
      const body = createTenancyBodySchema.parse(req.body ?? {});
      const ctx = getRlsCtx(req);

      const result = await withRlsTransaction(ctx, (client) =>
        createTenancy(client, {
          tenantId: body.tenantId,
          propertyId: body.propertyId,
          listingId: body.listingId ?? null,

          rentAmount: body.rentAmount,
          securityDeposit: body.securityDeposit ?? null,

          startDate: body.startDate,
          nextDueDate: body.nextDueDate,

          paymentCycle: (body.paymentCycle as any) ?? null,
          status: (body.status as any) ?? null,

          terminationReason: body.terminationReason ?? null,
        })
      );

      return { ok: true, data: result.row, reused: result.reused, patched: result.patched };
    }
  );

  /** END TENANCY */
  app.patch(
    "/v1/tenancies/:id/end",
    { preHandler: [app.authenticate] },
    async (req: FastifyRequest<{ Params: EndTenancyParams; Body: EndTenancyBody }>) => {
      const params = endTenancyParamsSchema.parse((req as any).params ?? {});
      const body = endTenancyBodySchema.parse((req as any).body ?? {});
      const ctx = getRlsCtx(req);

      const result = await withRlsTransaction(ctx, (client) =>
        endTenancy(client, {
          id: params.id,
          status: body.status,
          endDate: body.endDate ?? null,
          terminationReason: body.terminationReason ?? null,
        })
      );

      return { ok: true, data: result.row, changed: result.changed };
    }
  );

  /** START TENANCY (NEW) */
  app.patch(
    "/v1/tenancies/:id/start",
    { preHandler: [app.authenticate] },
    async (req: FastifyRequest<{ Params: StartTenancyParams; Body: StartTenancyBody }>) => {
      const params = startTenancyParamsSchema.parse((req as any).params ?? {});
      const body = startTenancyBodySchema.parse((req as any).body ?? {});
      const ctx = getRlsCtx(req);

      const result = await withRlsTransaction(ctx, (client) =>
        startTenancy(client, {
          id: params.id,
          startDate: body.startDate ?? null,
        })
      );

      return { ok: true, data: result.row, changed: result.changed };
    }
  );
}
EOF

echo "✅ Start Tenancy endpoint added."
echo ""
echo "Next:"
echo "  1) Restart TS Server in VS Code (Cmd+Shift+P -> TypeScript: Restart TS Server)"
echo "  2) Restart backend: npm run dev"
echo ""
echo "Test command (example):"
echo "  TENANCY_ID=\"<uuid>\""
echo "  curl -sS -X PATCH \"\$API/v1/tenancies/\$TENANCY_ID/start\" \\"
echo "    -H \"content-type: application/json\" \\"
echo "    -H \"authorization: Bearer \$TOKEN\" \\"
echo "    -H \"x-organization-id: \$ORG_ID\" \\"
echo "    -d '{\"startDate\":\"2026-02-01\"}' | jq"
