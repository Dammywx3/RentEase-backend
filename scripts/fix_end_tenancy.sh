#!/usr/bin/env bash
set -euo pipefail

# =========================
# 1) schemas: src/schemas/tenancies.schema.ts
# =========================
cat > src/schemas/tenancies.schema.ts <<'EOF'
import { z } from "zod";

export const tenancyStatusSchema = z.enum([
  "active",
  "ended",
  "terminated",
  "pending_start",
]);

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
  endDate: dateOnly.optional(), // if omitted server uses CURRENT_DATE
  terminationReason: z.string().max(5000).nullable().optional(),
});

export type EndTenancyBody = z.infer<typeof endTenancyBodySchema>;
export type EndTenancyParams = z.infer<typeof endTenancyParamsSchema>;
EOF

# =========================
# 2) repo: src/repos/tenancies.repo.ts
# =========================
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

const TENANCY_RETURNING = `
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

export async function findOpenTenancyByTenantProperty(
  client: PoolClient,
  tenantId: string,
  propertyId: string
): Promise<TenancyRow | null> {
  const { rows } = await client.query<TenancyRow>(
    `
    SELECT ${TENANCY_RETURNING}
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
        ${TENANCY_RETURNING},
        (
          (prev.listing_id IS NULL AND $2::uuid IS NOT NULL)
          OR (prev.security_deposit IS NULL AND $3::numeric IS NOT NULL)
          OR (prev.termination_reason IS NULL AND $4::text IS NOT NULL)
        ) AS patched
    )
    SELECT * FROM upd;
    `,
    [
      tenancyId,
      patch.listing_id ?? null,
      patch.security_deposit ?? null,
      patch.termination_reason ?? null,
    ]
  );

  const row = rows[0]!;
  const patched = (row as any).patched === true;
  delete (row as any).patched;

  return { row, patched };
}

export async function insertTenancy(
  client: PoolClient,
  data: InsertTenancyArgs
): Promise<TenancyRow> {
  const { rows } = await client.query<TenancyRow>(
    `
    INSERT INTO public.tenancies AS t (
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
    RETURNING ${TENANCY_RETURNING};
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
  const existing = await findOpenTenancyByTenantProperty(client, data.tenant_id, data.property_id);
  if (existing) {
    const patchedRes = await patchOpenTenancyMissingFields(client, existing.id, {
      listing_id: data.listing_id ?? null,
      security_deposit: data.security_deposit ?? null,
      termination_reason: data.termination_reason ?? null,
    });
    return { row: patchedRes.row, reused: true, patched: patchedRes.patched };
  }

  try {
    const row = await insertTenancy(client, data);
    return { row, reused: false, patched: false };
  } catch (err: any) {
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
    SELECT ${TENANCY_RETURNING}
    FROM public.tenancies t
    WHERE ${where.join(" AND ")}
    ORDER BY t.created_at DESC
    LIMIT $${limitIdx} OFFSET $${offsetIdx};
    `,
    params
  );

  return rows;
}

/** --- END TENANCY --- */
export async function endTenancyById(
  client: PoolClient,
  args: {
    id: string;
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
        t.deleted_at
      FROM public.tenancies t
      WHERE t.id = $1
      FOR UPDATE
    ),
    upd AS (
      UPDATE public.tenancies t
      SET
        status = $2::tenancy_status,
        end_date = COALESCE($3::date, CURRENT_DATE),
        termination_reason = COALESCE($4::text, t.termination_reason),
        updated_at = NOW()
      FROM prev
      WHERE t.id = prev.id
        AND prev.deleted_at IS NULL
        AND prev.status = ANY($5::tenancy_status[])
      RETURNING ${TENANCY_RETURNING}, true AS changed
    ),
    sel AS (
      SELECT ${TENANCY_RETURNING}, false AS changed
      FROM public.tenancies t
      JOIN prev ON prev.id = t.id
      WHERE NOT EXISTS (SELECT 1 FROM upd)
    )
    SELECT * FROM upd
    UNION ALL
    SELECT * FROM sel
    LIMIT 1;
    `,
    [
      args.id,
      args.status,
      args.end_date ?? null,
      args.termination_reason ?? null,
      OPEN_STATUSES,
    ]
  );

  const row = rows[0];
  if (!row) throw Object.assign(new Error("Tenancy not found"), { code: "NOT_FOUND" });

  const changed = (row as any).changed === true;
  delete (row as any).changed;

  return { row, changed };
}
EOF

# =========================
# 3) service: src/services/tenancies.service.ts
# =========================
cat > src/services/tenancies.service.ts <<'EOF'
import type { PoolClient } from "pg";
import {
  createTenancyIdempotent,
  endTenancyById,
  listTenancies,
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

/** --- END TENANCY --- */
export async function endTenancy(
  client: PoolClient,
  input: {
    id: string;
    status: "ended" | "terminated";
    endDate?: string | null;
    terminationReason?: string | null;
  }
): Promise<{ row: TenancyRow; changed: boolean }> {
  return endTenancyById(client, {
    id: input.id,
    status: input.status,
    end_date: input.endDate ?? null,
    termination_reason: input.terminationReason ?? null,
  });
}
EOF

# =========================
# 4) route: src/routes/tenancies.ts
# =========================
cat > src/routes/tenancies.ts <<'EOF'
import type { FastifyInstance, FastifyRequest } from "fastify";

import { withRlsTransaction } from "../db.js";
import {
  createTenancyBodySchema,
  endTenancyBodySchema,
  endTenancyParamsSchema,
  listTenanciesQuerySchema,
  type CreateTenancyBody,
  type EndTenancyBody,
  type EndTenancyParams,
  type ListTenanciesQuery,
} from "../schemas/tenancies.schema.js";
import { createTenancy, endTenancy, getTenancies } from "../services/tenancies.service.js";

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
      const q = listTenanciesQuerySchema.parse((req as any).query ?? {});
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
      const body = createTenancyBodySchema.parse((req as any).body ?? {});
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

  /** --- END TENANCY --- */
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
}
EOF

echo "✅ End-tenancy endpoint files updated."
echo "➡️  Restart the server (port 4000) and test PATCH /v1/tenancies/:id/end"
