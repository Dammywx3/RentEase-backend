#!/usr/bin/env bash
set -euo pipefail

# ---- 1) Schema ----
cat > src/schemas/tenancies.schema.ts <<'TS'
import { z } from "zod";

const dateOnly = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "must be YYYY-MM-DD");

export const tenancyStatusSchema = z.enum([
  "pending_start",
  "active",
  "ended",
  "terminated",
]);

export const createTenancyBodySchema = z.object({
  listingId: z.string().uuid(),
  propertyId: z.string().uuid(),
  tenantId: z.string().uuid(),

  startDate: dateOnly.optional(),
  endDate: dateOnly.optional(),

  rentAmount: z.number().positive().optional(),
  depositAmount: z.number().positive().optional(),

  // ✅ REQUIRED BY DB (NOT NULL) but we allow optional here because we auto-fill it in route/service
  nextDueDate: dateOnly.optional(),

  status: tenancyStatusSchema.optional(),
});

export const listTenanciesQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(10),
  offset: z.coerce.number().int().min(0).default(0),

  listingId: z.string().uuid().optional(),
  propertyId: z.string().uuid().optional(),
  tenantId: z.string().uuid().optional(),
  status: tenancyStatusSchema.optional(),
});

export const patchTenancyBodySchema = z.object({
  startDate: dateOnly.nullable().optional(),
  endDate: dateOnly.nullable().optional(),

  rentAmount: z.number().positive().nullable().optional(),
  depositAmount: z.number().positive().nullable().optional(),

  nextDueDate: dateOnly.nullable().optional(),

  status: tenancyStatusSchema.optional(),
});
TS

# ---- 2) Repo ----
cat > src/repos/tenancies.repo.ts <<'TS'
import type { PoolClient } from "pg";

export type TenancyStatus = "pending_start" | "active" | "ended" | "terminated";

export type TenancyRow = {
  id: string;
  listing_id: string;
  property_id: string;
  tenant_id: string;

  status: TenancyStatus | null;

  start_date: string | null;
  end_date: string | null;

  rent_amount: string | null;
  security_deposit: string | null;

  // ✅ NOT NULL in your schema
  next_due_date: string;

  created_at: string;
  updated_at: string;
};

export type InsertTenancyArgs = {
  listing_id: string;
  property_id: string;
  tenant_id: string;

  status?: TenancyStatus | null;

  start_date?: string | null;
  end_date?: string | null;

  rent_amount?: number | null;
  security_deposit?: number | null;

  // ✅ must be set (we'll also fallback to start_date or CURRENT_DATE)
  next_due_date?: string | null;
};

export async function insertTenancy(
  client: PoolClient,
  data: InsertTenancyArgs
): Promise<TenancyRow> {
  const { rows } = await client.query<TenancyRow>(
    `
    INSERT INTO public.tenancies (
      listing_id,
      property_id,
      tenant_id,
      status,
      start_date,
      end_date,
      rent_amount,
      security_deposit,
      next_due_date
    )
    VALUES (
      $1,$2,$3,
      COALESCE($4::tenancy_status, 'pending_start'::tenancy_status),
      $5::date,
      $6::date,
      $7,
      $8,
      COALESCE($9::date, $5::date, CURRENT_DATE)
    )
    RETURNING *;
    `,
    [
      data.listing_id,
      data.property_id,
      data.tenant_id,
      data.status ?? null,
      data.start_date ?? null,
      data.end_date ?? null,
      data.rent_amount ?? null,
      data.security_deposit ?? null,
      data.next_due_date ?? null,
    ]
  );

  return rows[0]!;
}

export async function getTenancyById(
  client: PoolClient,
  id: string
): Promise<TenancyRow | null> {
  const { rows } = await client.query<TenancyRow>(
    `SELECT * FROM public.tenancies WHERE id = $1 LIMIT 1`,
    [id]
  );
  return rows[0] ?? null;
}

export async function listTenancies(
  client: PoolClient,
  args: {
    limit: number;
    offset: number;
    listing_id?: string;
    property_id?: string;
    tenant_id?: string;
    status?: TenancyStatus;
  }
): Promise<TenancyRow[]> {
  const where: string[] = ["1=1"];
  const params: any[] = [];
  let i = 1;

  if (args.listing_id) { where.push(`listing_id = $${i++}`); params.push(args.listing_id); }
  if (args.property_id){ where.push(`property_id = $${i++}`); params.push(args.property_id); }
  if (args.tenant_id)  { where.push(`tenant_id = $${i++}`); params.push(args.tenant_id); }
  if (args.status)     { where.push(`status = $${i++}::tenancy_status`); params.push(args.status); }

  params.push(args.limit);  const limitIdx = i++;
  params.push(args.offset); const offsetIdx = i++;

  const { rows } = await client.query<TenancyRow>(
    `
    SELECT *
    FROM public.tenancies
    WHERE ${where.join(" AND ")}
    ORDER BY created_at DESC
    LIMIT $${limitIdx} OFFSET $${offsetIdx}
    `,
    params
  );

  return rows;
}

export async function patchTenancy(
  client: PoolClient,
  id: string,
  patch: Partial<{
    status: TenancyStatus | null;
    start_date: string | null;
    end_date: string | null;
    rent_amount: number | null;
    security_deposit: number | null;
    next_due_date: string | null;
  }>
): Promise<TenancyRow | null> {
  const sets: string[] = ["updated_at = now()"];
  const params: any[] = [];
  let i = 1;

  for (const [k, v] of Object.entries(patch)) {
    if (k === "start_date" || k === "end_date" || k === "next_due_date") {
      sets.push(`${k} = $${i++}::date`);
      params.push(v);
      continue;
    }
    if (k === "status") {
      sets.push(`${k} = $${i++}::tenancy_status`);
      params.push(v);
      continue;
    }
    sets.push(`${k} = $${i++}`);
    params.push(v);
  }

  params.push(id);

  const { rows } = await client.query<TenancyRow>(
    `
    UPDATE public.tenancies
    SET ${sets.join(", ")}
    WHERE id = $${i}
    RETURNING *;
    `,
    params
  );

  return rows[0] ?? null;
}
TS

# ---- 3) Service ----
cat > src/services/tenancies.service.ts <<'TS'
import type { PoolClient } from "pg";
import {
  insertTenancy,
  getTenancyById,
  listTenancies,
  patchTenancy,
  type TenancyStatus,
} from "../repos/tenancies.repo.js";

export async function createTenancy(
  client: PoolClient,
  data: {
    listing_id: string;
    property_id: string;
    tenant_id: string;

    start_date?: string | null;
    end_date?: string | null;

    rent_amount?: number | null;
    security_deposit?: number | null;

    next_due_date?: string | null;

    status?: TenancyStatus | null;
  }
) {
  return insertTenancy(client, data);
}

export async function getTenancy(client: PoolClient, id: string) {
  return getTenancyById(client, id);
}

export async function listAllTenancies(
  client: PoolClient,
  args: {
    limit: number;
    offset: number;
    listing_id?: string;
    property_id?: string;
    tenant_id?: string;
    status?: TenancyStatus;
  }
) {
  return listTenancies(client, args);
}

export async function updateTenancy(
  client: PoolClient,
  id: string,
  patch: any
) {
  return patchTenancy(client, id, patch);
}
TS

# ---- 4) Routes ----
cat > src/routes/tenancies.ts <<'TS'
import type { FastifyInstance } from "fastify";
import type { PoolClient } from "pg";
import { withRlsTransaction } from "../config/database.js";

import {
  createTenancy,
  getTenancy,
  listAllTenancies,
  updateTenancy,
} from "../services/tenancies.service.js";

import {
  createTenancyBodySchema,
  listTenanciesQuerySchema,
  patchTenancyBodySchema,
} from "../schemas/tenancies.schema.js";

function dateOnly(v: unknown): string | null {
  if (v === null || v === undefined) return null;
  if (v instanceof Date && !Number.isNaN(v.getTime())) return v.toISOString().slice(0, 10);
  if (typeof v === "string") return v.includes("T") ? v.slice(0, 10) : v;
  return null;
}

export async function tenancyRoutes(app: FastifyInstance) {
  app.get("/v1/tenancies", { preHandler: [app.authenticate] }, async (req) => {
    const q = listTenanciesQuerySchema.parse(req.query ?? {});
    const userId = req.user.sub;
    const orgId = req.user.org;

    const data = await withRlsTransaction(
      { userId, organizationId: orgId },
      async (client: PoolClient) =>
        listAllTenancies(client, {
          limit: q.limit,
          offset: q.offset,
          listing_id: q.listingId,
          property_id: q.propertyId,
          tenant_id: q.tenantId,
          status: q.status ?? undefined,
        })
    );

    return { ok: true, data, paging: { limit: q.limit, offset: q.offset } };
  });

  app.get("/v1/tenancies/:id", { preHandler: [app.authenticate] }, async (req) => {
    const { id } = req.params as any;
    const userId = req.user.sub;
    const orgId = req.user.org;

    const data = await withRlsTransaction(
      { userId, organizationId: orgId },
      async (client: PoolClient) => getTenancy(client, String(id))
    );

    return { ok: true, data };
  });

  app.post("/v1/tenancies", { preHandler: [app.authenticate] }, async (req) => {
    const body = createTenancyBodySchema.parse(req.body ?? {});
    const userId = req.user.sub;
    const orgId = req.user.org;

    const startDate = dateOnly(body.startDate);
    const nextDue = dateOnly(body.nextDueDate) ?? startDate ?? new Date().toISOString().slice(0, 10);

    const data = await withRlsTransaction(
      { userId, organizationId: orgId },
      async (client: PoolClient) =>
        createTenancy(client, {
          listing_id: body.listingId,
          property_id: body.propertyId,
          tenant_id: body.tenantId,

          start_date: startDate,
          end_date: dateOnly(body.endDate),

          rent_amount: body.rentAmount ?? null,
          security_deposit: body.depositAmount ?? null,

          // ✅ satisfy NOT NULL schema
          next_due_date: nextDue,

          status: body.status ?? null,
        })
    );

    return { ok: true, data };
  });

  app.patch("/v1/tenancies/:id", { preHandler: [app.authenticate] }, async (req) => {
    const { id } = req.params as any;
    const body = patchTenancyBodySchema.parse(req.body ?? {});
    const userId = req.user.sub;
    const orgId = req.user.org;

    const patch: any = {};
    if (body.status !== undefined) patch.status = body.status;
    if (body.startDate !== undefined) patch.start_date = dateOnly(body.startDate);
    if (body.endDate !== undefined) patch.end_date = dateOnly(body.endDate);
    if (body.rentAmount !== undefined) patch.rent_amount = body.rentAmount;
    if (body.depositAmount !== undefined) patch.security_deposit = body.depositAmount;
    if (body.nextDueDate !== undefined) patch.next_due_date = dateOnly(body.nextDueDate);

    const data = await withRlsTransaction(
      { userId, organizationId: orgId },
      async (client: PoolClient) => updateTenancy(client, String(id), patch)
    );

    return { ok: true, data };
  });
}
TS

# ---- 5) Test Script ----
cat > scripts/test_tenancies.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail

API="${API:-http://127.0.0.1:4000}"
DB_NAME="${DB_NAME:-rentease}"

eval "$(./scripts/login.sh)"
echo "✅ TOKEN set"

ME_ID="$(curl -s $API/v1/me -H "authorization: Bearer $TOKEN" | jq -r '.data.id')"
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
    \"listingId\":\"$LISTING_ID\",
    \"propertyId\":\"$PROPERTY_ID\",
    \"tenantId\":\"$ME_ID\",
    \"startDate\":\"2026-02-01\",
    \"nextDueDate\":\"2026-03-01\",
    \"rentAmount\":2000,
    \"depositAmount\":500,
    \"status\":\"pending_start\"
  }" | jq

echo
echo "Listing tenancies..."
curl -s "$API/v1/tenancies?limit=10&offset=0" -H "authorization: Bearer $TOKEN" | jq

echo
echo "DB check: tenancies (last 5)"
PAGER=cat psql -d "$DB_NAME" -c "select id, listing_id, tenant_id, status, start_date, next_due_date, rent_amount, security_deposit, created_at from tenancies order by created_at desc limit 5;"
SH
chmod +x scripts/test_tenancies.sh

# ---- routes/index.ts: ensure tenancyRoutes is imported and registered ONCE ----
if [ -f src/routes/index.ts ]; then
  # remove duplicate lines (keep first)
  perl -pi -e 'BEGIN{$seen=0} if(/await\s+app\.register\(tenancyRoutes\);/){ if($seen++){ $_="" } }' src/routes/index.ts

  # add import if missing
  if ! grep -q 'from "\.\/tenancies\.js"' src/routes/index.ts; then
    perl -0777 -pi -e 's/(import\s+\{\s*applicationRoutes\s*\}\s+from\s+"\.\/applications\.js";\s*\n)/$1import { tenancyRoutes } from "\.\/tenancies\.js";\n/s' src/routes/index.ts \
      || perl -0777 -pi -e 's/(import\s+\{\s*listingRoutes\s*\}\s+from\s+"\.\/listings\.js";\s*\n)/$1import { tenancyRoutes } from "\.\/tenancies\.js";\n/s' src/routes/index.ts \
      || perl -0777 -pi -e 's/(import\s+\{\s*propertyRoutes\s*\}\s+from\s+"\.\/properties\.js";\s*\n)/$1import { tenancyRoutes } from "\.\/tenancies\.js";\n/s' src/routes/index.ts
  fi

  # register if missing (place after applicationRoutes if present else after listingRoutes else after propertyRoutes)
  if ! grep -q 'app\.register\(tenancyRoutes\)' src/routes/index.ts; then
    perl -0777 -pi -e 's/(await app\.register\(applicationRoutes\);\s*\n)/$1  await app.register(tenancyRoutes);\n/s' src/routes/index.ts \
      || perl -0777 -pi -e 's/(await app\.register\(listingRoutes\);\s*\n)/$1  await app.register(tenancyRoutes);\n/s' src/routes/index.ts \
      || perl -0777 -pi -e 's/(await app\.register\(propertyRoutes\);\s*\n)/$1  await app.register(tenancyRoutes);\n/s' src/routes/index.ts
  fi

  # remove duplicates again (just in case)
  perl -pi -e 'BEGIN{$seen=0} if(/await\s+app\.register\(tenancyRoutes\);/){ if($seen++){ $_="" } }' src/routes/index.ts
fi

echo "✅ Tenancies fixed to match schema (next_due_date NOT NULL handled)."
echo "Next:"
echo "  npm run dev"
echo "  ./scripts/test_tenancies.sh"
