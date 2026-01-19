#!/usr/bin/env bash
set -euo pipefail

DB_NAME="${DB_NAME:-rentease}"
API="${API:-http://127.0.0.1:4000}"

mkdir -p src/schemas src/repos src/services src/routes scripts

# ----------------------------
# 1) Schema (Zod)
# ----------------------------
cat > src/schemas/tenancies.schema.ts <<'TS'
import { z } from "zod";

export const tenancyStatusSchema = z.enum([
  "active",
  "ended",
  "terminated",
  "pending_start",
]);

export const createTenancyBodySchema = z.object({
  listingId: z.string().uuid(),
  propertyId: z.string().uuid(),

  // Date-only (matches DB DATE)
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "startDate must be YYYY-MM-DD").optional(),
  endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "endDate must be YYYY-MM-DD").optional(),

  rentAmount: z.number().positive().optional(),
  securityDeposit: z.number().nonnegative().optional(),

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
  status: tenancyStatusSchema.optional(),

  startDate: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/, "startDate must be YYYY-MM-DD")
    .nullable()
    .optional(),

  endDate: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/, "endDate must be YYYY-MM-DD")
    .nullable()
    .optional(),

  rentAmount: z.number().positive().nullable().optional(),
  securityDeposit: z.number().nonnegative().nullable().optional(),
});
TS

# ----------------------------
# 2) Repo (SQL) - MATCHES YOUR DB
#    public.tenancies(
#      id, listing_id, property_id, tenant_id,
#      status (tenancy_status),
#      start_date, end_date, rent_amount, security_deposit,
#      created_at, updated_at
#    )
# ----------------------------
cat > src/repos/tenancies.repo.ts <<'TS'
import type { PoolClient } from "pg";

export type TenancyStatus = "active" | "ended" | "terminated" | "pending_start";

export type TenancyRow = {
  id: string;
  listing_id: string;
  property_id: string;
  tenant_id: string;

  status: TenancyStatus | null;

  start_date: string | null;         // DATE -> "YYYY-MM-DD"
  end_date: string | null;           // DATE -> "YYYY-MM-DD"
  rent_amount: string | null;        // numeric -> pg returns string
  security_deposit: string | null;   // numeric -> pg returns string

  created_at: string;
  updated_at: string;
};

export type InsertTenancyArgs = {
  listing_id: string;
  property_id: string;
  tenant_id: string;

  start_date?: string | null;
  end_date?: string | null;
  rent_amount?: number | null;
  security_deposit?: number | null;

  status?: TenancyStatus | null;
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
      security_deposit
    )
    VALUES (
      $1, $2, $3,
      COALESCE($4::tenancy_status, 'pending_start'::tenancy_status),
      $5::date,
      $6::date,
      $7,
      $8
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

  if (args.listing_id) {
    where.push(`listing_id = $${i++}`);
    params.push(args.listing_id);
  }
  if (args.property_id) {
    where.push(`property_id = $${i++}`);
    params.push(args.property_id);
  }
  if (args.tenant_id) {
    where.push(`tenant_id = $${i++}`);
    params.push(args.tenant_id);
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
  }>
): Promise<TenancyRow | null> {
  const sets: string[] = ["updated_at = now()"];
  const params: any[] = [];
  let i = 1;

  for (const [k, v] of Object.entries(patch)) {
    if (k === "start_date" || k === "end_date") {
      sets.push(`${k} = $${i++}::date`);
      params.push(v);
      continue;
    }
    if (k === "status") {
      sets.push(`status = $${i++}::tenancy_status`);
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

# ----------------------------
# 3) Service
# ----------------------------
cat > src/services/tenancies.service.ts <<'TS'
import type { PoolClient } from "pg";
import type { TenancyStatus } from "../repos/tenancies.repo.js";
import {
  insertTenancy,
  getTenancyById,
  listTenancies,
  patchTenancy,
} from "../repos/tenancies.repo.js";

export async function createTenancy(
  client: PoolClient,
  ctx: { userId: string },
  data: {
    listing_id: string;
    property_id: string;
    start_date?: string | null;
    end_date?: string | null;
    rent_amount?: number | null;
    security_deposit?: number | null;
    status?: TenancyStatus | null;
  }
) {
  // tenant_id always current user for now (matches your RLS patterns)
  return insertTenancy(client, {
    listing_id: data.listing_id,
    property_id: data.property_id,
    tenant_id: ctx.userId,
    start_date: data.start_date ?? null,
    end_date: data.end_date ?? null,
    rent_amount: data.rent_amount ?? null,
    security_deposit: data.security_deposit ?? null,
    status: data.status ?? null,
  });
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
  patch: Partial<{
    status: TenancyStatus | null;
    start_date: string | null;
    end_date: string | null;
    rent_amount: number | null;
    security_deposit: number | null;
  }>
) {
  return patchTenancy(client, id, patch);
}
TS

# ----------------------------
# 4) Routes
# ----------------------------
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

function normalizeDateOnly(v: unknown): string | null {
  if (v === null || v === undefined) return null;
  if (typeof v === "string") return v.includes("T") ? v.slice(0, 10) : v;
  if (v instanceof Date && !Number.isNaN(v.getTime())) return v.toISOString().slice(0, 10);
  return null;
}

export async function tenancyRoutes(app: FastifyInstance) {
  app.get("/v1/tenancies", { preHandler: [app.authenticate] }, async (req) => {
    const q = listTenanciesQuerySchema.parse(req.query ?? {});
    const userId = req.user.sub;
    const orgId = req.user.org;

    const data = await withRlsTransaction(
      { userId, organizationId: orgId },
      async (client: PoolClient) => {
        return listAllTenancies(client, {
          limit: q.limit,
          offset: q.offset,
          listing_id: q.listingId,
          property_id: q.propertyId,
          tenant_id: q.tenantId,
          status: q.status ?? undefined,
        });
      }
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

    const data = await withRlsTransaction(
      { userId, organizationId: orgId },
      async (client: PoolClient) => {
        return createTenancy(client, { userId }, {
          listing_id: body.listingId,
          property_id: body.propertyId,
          start_date: normalizeDateOnly(body.startDate),
          end_date: normalizeDateOnly(body.endDate),
          rent_amount: body.rentAmount ?? null,
          security_deposit: body.securityDeposit ?? null,
          status: body.status ?? null,
        });
      }
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
    if (body.startDate !== undefined) patch.start_date = normalizeDateOnly(body.startDate);
    if (body.endDate !== undefined) patch.end_date = normalizeDateOnly(body.endDate);
    if (body.rentAmount !== undefined) patch.rent_amount = body.rentAmount;
    if (body.securityDeposit !== undefined) patch.security_deposit = body.securityDeposit;

    const data = await withRlsTransaction(
      { userId, organizationId: orgId },
      async (client: PoolClient) => updateTenancy(client, String(id), patch)
    );

    return { ok: true, data };
  });
}
TS

# ----------------------------
# 5) Test script
# ----------------------------
cat > scripts/test_tenancies.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail

API="${API:-http://127.0.0.1:4000}"

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
    \"startDate\":\"2026-02-01\",
    \"endDate\":\"2027-01-31\",
    \"rentAmount\":1500,
    \"securityDeposit\":1500,
    \"status\":\"pending_start\"
  }" | jq

echo
echo "Listing tenancies..."
curl -s "$API/v1/tenancies?limit=10&offset=0" -H "authorization: Bearer $TOKEN" | jq

echo
echo "DB check: tenancies (last 5)"
PAGER=cat psql -d rentease -c "select id, listing_id, tenant_id, status, start_date, end_date, rent_amount, security_deposit, created_at from tenancies order by created_at desc limit 5;"
SH
chmod +x scripts/test_tenancies.sh

# ----------------------------
# Update src/routes/index.ts (import + register ONCE; remove duplicates)
# ----------------------------
if [ -f src/routes/index.ts ]; then
  # remove duplicate register lines (keep first)
  perl -pi -e 'BEGIN{$seen=0} if(/await\s+app\.register\(tenancyRoutes\);/){ if($seen++){ $_="" } }' src/routes/index.ts

  # add import if missing
  if ! grep -q 'from "\.\/tenancies\.js"' src/routes/index.ts; then
    perl -0777 -pi -e 's/(import\s+\{\s*applicationRoutes\s*\}\s+from\s+"\.\/applications\.js";\s*\n)/$1import { tenancyRoutes } from "\.\/tenancies\.js";\n/s' src/routes/index.ts \
      || perl -0777 -pi -e 's/(import\s+\{\s*listingRoutes\s*\}\s+from\s+"\.\/listings\.js";\s*\n)/$1import { tenancyRoutes } from "\.\/tenancies\.js";\n/s' src/routes/index.ts \
      || perl -0777 -pi -e 's/(import\s+\{\s*viewingRoutes\s*\}\s+from\s+"\.\/viewings\.js";\s*\n)/$1import { tenancyRoutes } from "\.\/tenancies\.js";\n/s' src/routes/index.ts \
      || perl -0777 -pi -e 's/(import\s+\{\s*propertyRoutes\s*\}\s+from\s+"\.\/properties\.js";\s*\n)/$1import { tenancyRoutes } from "\.\/tenancies\.js";\n/s' src/routes/index.ts
  fi

  # register if missing (put after applicationRoutes if present, else after listingRoutes, else after viewingRoutes, else after propertyRoutes)
  if ! grep -q 'app\.register\(tenancyRoutes\)' src/routes/index.ts; then
    perl -0777 -pi -e 's/(await app\.register\(applicationRoutes\);\s*\n)/$1  await app.register(tenancyRoutes);\n/s' src/routes/index.ts \
      || perl -0777 -pi -e 's/(await app\.register\(listingRoutes\);\s*\n)/$1  await app.register(tenancyRoutes);\n/s' src/routes/index.ts \
      || perl -0777 -pi -e 's/(await app\.register\(viewingRoutes\);\s*\n)/$1  await app.register(tenancyRoutes);\n/s' src/routes/index.ts \
      || perl -0777 -pi -e 's/(await app\.register\(propertyRoutes\);\s*\n)/$1  await app.register(tenancyRoutes);\n/s' src/routes/index.ts
  fi
fi

echo "✅ Wrote 5 files:"
echo "  - src/schemas/tenancies.schema.ts"
echo "  - src/repos/tenancies.repo.ts"
echo "  - src/services/tenancies.service.ts"
echo "  - src/routes/tenancies.ts"
echo "  - scripts/test_tenancies.sh"
echo "✅ Updated: src/routes/index.ts (import + register tenancyRoutes once)"
echo
echo "Next:"
echo "  npm run dev"
echo "  ./scripts/test_tenancies.sh"
