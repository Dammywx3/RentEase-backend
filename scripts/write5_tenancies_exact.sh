#!/usr/bin/env bash
set -euo pipefail

mkdir -p src/schemas src/repos src/services src/routes scripts

cat > src/schemas/tenancies.schema.ts <<'TS'
import { z } from "zod";

export const tenancyStatusSchema = z.enum([
  "active",
  "ended",
  "terminated",
  "pending_start",
]);

const dateOnly = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Expected YYYY-MM-DD");

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

export const listTenanciesQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(10),
  offset: z.coerce.number().int().min(0).default(0),

  tenantId: z.string().uuid().optional(),
  propertyId: z.string().uuid().optional(),
  listingId: z.string().uuid().optional(),
  status: tenancyStatusSchema.optional(),
});
TS

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

  start_date: string;
  end_date: string | null;
  next_due_date: string;

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

  start_date: string;
  next_due_date: string;

  payment_cycle?: string | null;
  status?: TenancyStatus | null;

  termination_reason?: string | null;
};

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
    RETURNING *;
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

export async function listTenancies(
  client: PoolClient,
  args: { limit: number; offset: number; tenant_id?: string; property_id?: string; listing_id?: string; status?: TenancyStatus }
): Promise<TenancyRow[]> {
  const where: string[] = ["deleted_at IS NULL"];
  const params: any[] = [];
  let i = 1;

  if (args.tenant_id)   { where.push(`tenant_id = $${i++}`); params.push(args.tenant_id); }
  if (args.property_id) { where.push(`property_id = $${i++}`); params.push(args.property_id); }
  if (args.listing_id)  { where.push(`listing_id = $${i++}`); params.push(args.listing_id); }
  if (args.status)      { where.push(`status = $${i++}::tenancy_status`); params.push(args.status); }

  params.push(args.limit);  const limitIdx = i++;
  params.push(args.offset); const offsetIdx = i++;

  const { rows } = await client.query<TenancyRow>(
    `
    SELECT *
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

cat > src/services/tenancies.service.ts <<'TS'
import type { PoolClient } from "pg";
import { insertTenancy, listTenancies, type TenancyStatus, type TenancyRow } from "../repos/tenancies.repo.js";

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
): Promise<TenancyRow> {
  return insertTenancy(client, {
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

cat > src/routes/tenancies.ts <<'TS'
import type { FastifyInstance } from "fastify";
import { withRlsTransaction } from "../db.js";
import { createTenancyBodySchema, listTenanciesQuerySchema } from "../schemas/tenancies.schema.js";
import { createTenancy, getTenancies } from "../services/tenancies.service.js";

export async function tenancyRoutes(app: FastifyInstance) {
  app.get("/v1/tenancies", { preHandler: [app.authenticate] }, async (req) => {
    const q = listTenanciesQuerySchema.parse((req as any).query ?? {});
    const ctx = (req as any).rls;

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
    const ctx = (req as any).rls;

    const data = await withRlsTransaction(ctx, (client) =>
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

    return { ok: true, data };
  });
}
TS

cat > scripts/test_tenancies.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail

API="${API:-http://127.0.0.1:4000}"
DB_NAME="${DB_NAME:-rentease}"

eval "$(./scripts/login.sh)"
echo "✅ TOKEN set"

ME_ID="$(curl -s "$API/v1/me" -H "authorization: Bearer $TOKEN" | jq -r '.data.id')"
PROPERTY_ID="$(curl -s "$API/v1/properties?limit=1&offset=0" -H "authorization: Bearer $TOKEN" | jq -r '.data[0].id')"
LISTING_ID="$(curl -s "$API/v1/listings?limit=1&offset=0" -H "authorization: Bearer $TOKEN" | jq -r '.data[0].id')"

echo "ME_ID=$ME_ID"
echo "PROPERTY_ID=$PROPERTY_ID"
echo "LISTING_ID=$LISTING_ID"

echo
echo "Creating tenancy..."
curl -s -X POST "$API/v1/tenancies" \
  -H "content-type: application/json" \
  -H "authorization: Bearer $TOKEN" \
  -d "{
    \"tenantId\":\"$ME_ID\",
    \"propertyId\":\"$PROPERTY_ID\",
    \"listingId\":\"$LISTING_ID\",
    \"rentAmount\":2000,
    \"securityDeposit\":500,
    \"startDate\":\"2026-02-01\",
    \"nextDueDate\":\"2026-03-01\",
    \"status\":\"pending_start\"
  }" | jq

echo
echo "Listing tenancies..."
curl -s "$API/v1/tenancies?limit=10&offset=0" -H "authorization: Bearer $TOKEN" | jq

echo
echo "DB check: tenancies (last 5)"
PAGER=cat psql -d "$DB_NAME" -c "select id, tenant_id, property_id, listing_id, status, start_date, next_due_date, rent_amount, security_deposit, created_at from tenancies order by created_at desc limit 5;"
SH
chmod +x scripts/test_tenancies.sh

# --- register tenancyRoutes ONCE ---
if [ -f src/routes/index.ts ]; then
  if ! grep -q 'from "\.\/tenancies\.js"' src/routes/index.ts; then
    perl -0777 -pi -e 's/(import\s+\{\s*applicationRoutes\s*\}\s+from\s+"\.\/applications\.js";\s*\n)/$1import { tenancyRoutes } from "\.\/tenancies\.js";\n/s' src/routes/index.ts
  fi

  perl -pi -e 'BEGIN{$seen=0} if(/await\s+app\.register\(tenancyRoutes\);/){ if($seen++){ $_="" } }' src/routes/index.ts

  if ! grep -q 'await app\.register\(tenancyRoutes\);' src/routes/index.ts; then
    perl -0777 -pi -e 's/(await app\.register\(applicationRoutes\);\s*\n)/$1  await app.register(tenancyRoutes);\n/s' src/routes/index.ts
  fi
fi

echo "✅ Wrote tenancy files + test script."
echo "Next:"
echo "  bash scripts/write5_tenancies_exact.sh"
echo "  npm run dev"
echo "  ./scripts/test_tenancies.sh"
