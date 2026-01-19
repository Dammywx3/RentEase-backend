#!/usr/bin/env bash
set -euo pipefail

# ---------- 1) Repo: idempotent create + race-safe ----------
cat > src/repos/tenancies.repo.ts <<'TS'
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

  start_date: string;           // YYYY-MM-DD
  end_date: string | null;      // YYYY-MM-DD or null
  next_due_date: string;        // YYYY-MM-DD

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

  start_date: string;      // YYYY-MM-DD
  next_due_date: string;   // YYYY-MM-DD

  payment_cycle?: string | null;
  status?: TenancyStatus | null;

  termination_reason?: string | null;
};

// Reusable SELECT list (casts DATE -> TEXT so API returns "YYYY-MM-DD")
const TENANCY_SELECT = `
  id,
  tenant_id,
  property_id,
  listing_id,
  rent_amount,
  security_deposit,
  payment_cycle,
  start_date::text    AS start_date,
  end_date::text      AS end_date,
  next_due_date::text AS next_due_date,
  notice_period_days,
  status,
  termination_reason,
  late_fee_percentage,
  grace_period_days,
  created_at,
  updated_at,
  deleted_at,
  version
`;

const OPEN_STATUSES: TenancyStatus[] = ["active", "pending_start"];

export async function findOpenTenancyByTenantProperty(
  client: PoolClient,
  tenantId: string,
  propertyId: string
): Promise<TenancyRow | null> {
  const { rows } = await client.query<TenancyRow>(
    `
    SELECT ${TENANCY_SELECT}
    FROM public.tenancies
    WHERE tenant_id = $1
      AND property_id = $2
      AND deleted_at IS NULL
      AND status = ANY($3::tenancy_status[])
    ORDER BY created_at DESC
    LIMIT 1;
    `,
    [tenantId, propertyId, OPEN_STATUSES]
  );
  return rows[0] ?? null;
}

export async function insertTenancy(
  client: PoolClient,
  data: InsertTenancyArgs
): Promise<TenancyRow> {
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
      COALESCE($8::payment_cycle, monthly::payment_cycle),
      COALESCE($9::tenancy_status, pending_start::tenancy_status),
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

/**
 * Best practice: idempotent create for "open tenancy" uniqueness.
 * - If an open tenancy already exists (active/pending_start, not deleted), return it (reused=true).
 * - Else try insert (reused=false).
 * - If insert hits unique constraint (race), load & return existing (reused=true).
 */
export async function createTenancyIdempotent(
  client: PoolClient,
  data: InsertTenancyArgs
): Promise<{ row: TenancyRow; reused: boolean }> {
  // Fast path: already exists
  const existing = await findOpenTenancyByTenantProperty(client, data.tenant_id, data.property_id);
  if (existing) return { row: existing, reused: true };

  try {
    const row = await insertTenancy(client, data);
    return { row, reused: false };
  } catch (err: any) {
    // Race-safe: if another request created it first, unique index blocks this insert.
    const code = err?.code;
    const constraint = err?.constraint;

    if (code === "23505" && constraint === "uniq_open_tenancy") {
      const again = await findOpenTenancyByTenantProperty(client, data.tenant_id, data.property_id);
      if (again) return { row: again, reused: true };
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
  const where: string[] = ["deleted_at IS NULL"];
  const params: any[] = [];
  let i = 1;

  if (args.tenant_id) {
    where.push(`tenant_id = $${i++}`);
    params.push(args.tenant_id);
  }
  if (args.property_id) {
    where.push(`property_id = $${i++}`);
    params.push(args.property_id);
  }
  if (args.listing_id) {
    where.push(`listing_id = $${i++}`);
    params.push(args.listing_id);
  }
  if (args.status) {
    where.push(`status = $${i++}::tenancy_status`);
    params.push(args.status);
  }

  params.push(args.limit);
  const limitIdx = i++;
  params.push(args.offset);
  const offsetIdx = i++;

  const { rows } = await client.query<TenancyRow>(
    `
    SELECT ${TENANCY_SELECT}
    FROM public.tenancies
    WHERE ${where.join(" AND ")}
    ORDER BY created_at DESC
    LIMIT $${limitIdx} OFFSET $${offsetIdx};
    `,
    params
  );

  return rows;
}
TS

# ---------- 2) Service: use idempotent create ----------
cat > src/services/tenancies.service.ts <<'TS'
import type { PoolClient } from "pg";
import {
  createTenancyIdempotent,
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
): Promise<{ row: TenancyRow; reused: boolean }> {
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
TS

# ---------- 3) Route: keep your ctx logic, return reused flag ----------
cat > src/routes/tenancies.ts <<'TS'
import type { FastifyInstance } from "fastify";

import { withRlsTransaction } from "../db.js";
import { createTenancyBodySchema, listTenanciesQuerySchema } from "../schemas/tenancies.schema.js";
import { createTenancy, getTenancies } from "../services/tenancies.service.js";

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
  app.get("/v1/tenancies", { preHandler: [app.authenticate] }, async (req) => {
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
  });

  app.post("/v1/tenancies", { preHandler: [app.authenticate] }, async (req) => {
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

    return { ok: true, data: result.row, reused: result.reused };
  });
}
TS

# ---------- 4) Test: prove idempotency (POST twice returns same open tenancy) ----------
cat > scripts/test_tenancies.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail

API="${API:-http://127.0.0.1:4000}"
DB_NAME="${DB_NAME:-rentease}"

eval "$(./scripts/login.sh)"
echo "✅ TOKEN set"

ME_ID="$(curl -s $API/v1/me -H "authorization: Bearer $TOKEN" | jq -r ".data.id")"
ORG_ID="$(curl -s $API/v1/me -H "authorization: Bearer $TOKEN" | jq -r ".data.organization_id // .data.organizationId")"
PROPERTY_ID="$(curl -s "$API/v1/properties?limit=1&offset=0" -H "authorization: Bearer $TOKEN" -H "x-organization-id: $ORG_ID" | jq -r ".data[0].id")"
LISTING_ID="$(curl -s "$API/v1/listings?limit=1&offset=0" -H "authorization: Bearer $TOKEN" -H "x-organization-id: $ORG_ID" | jq -r ".data[0].id")"

echo "ME_ID=$ME_ID"
echo "ORG_ID=$ORG_ID"
echo "PROPERTY_ID=$PROPERTY_ID"
echo "LISTING_ID=$LISTING_ID"

BODY=$(cat <<JSON
{
  "listingId":"$LISTING_ID",
  "propertyId":"$PROPERTY_ID",
  "tenantId":"$ME_ID",
  "startDate":"2026-02-01",
  "nextDueDate":"2026-03-01",
  "rentAmount":2000,
  "depositAmount":500,
  "status":"pending_start"
}
JSON
)

echo
echo "POST #1 (should create or reuse)..."
R1=$(curl -s -X POST "$API/v1/tenancies" \
  -H "content-type: application/json" \
  -H "authorization: Bearer $TOKEN" \
  -H "x-organization-id: $ORG_ID" \
  -d "$BODY")
echo "$R1" | jq
ID1=$(echo "$R1" | jq -r ".data.id")

echo
echo "POST #2 (should NOT 23505; should reuse and return same open tenancy)..."
R2=$(curl -s -X POST "$API/v1/tenancies" \
  -H "content-type: application/json" \
  -H "authorization: Bearer $TOKEN" \
  -H "x-organization-id: $ORG_ID" \
  -d "$BODY")
echo "$R2" | jq
ID2=$(echo "$R2" | jq -r ".data.id")

echo
if [ "$ID1" = "$ID2" ]; then
  echo "✅ Idempotent: same tenancy returned on repeat POST (id=$ID2)"
else
  echo "⚠️ Different IDs returned (unexpected): $ID1 vs $ID2"
fi

echo
echo "Listing tenancies (API)..."
curl -s "$API/v1/tenancies?limit=10&offset=0" \
  -H "authorization: Bearer $TOKEN" \
  -H "x-organization-id: $ORG_ID" | jq

echo
echo "DB check: open tenancies for this tenant+property (deleted_at IS NULL only)"
PAGER=cat psql -d "$DB_NAME" -c "
select id, status, deleted_at, created_at
from public.tenancies
where tenant_id = '$ME_ID'
  and property_id = '$PROPERTY_ID'
  and deleted_at is null
  and status in ('active','pending_start')
order by created_at desc;
"
SH

chmod +x scripts/test_tenancies.sh

echo "✅ Applied idempotent tenancy create (repo+service+route) + updated test script."
