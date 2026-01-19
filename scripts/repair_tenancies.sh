#!/usr/bin/env bash
set -euo pipefail

mkdir -p scripts src/schemas src/repos src/services src/routes

# -----------------------------
# 1) Tenancies Zod schemas
# -----------------------------
cat > src/schemas/tenancies.schema.ts <<'TS'
import { z } from "zod";

export const tenancyStatusSchema = z.enum([
  "active",
  "ended",
  "terminated",
  "pending_start",
]);

const dateOnly = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "must be YYYY-MM-DD");

export const createTenancyBodySchema = z.object({
  listingId: z.string().uuid(),
  propertyId: z.string().uuid(),
  tenantId: z.string().uuid(),

  startDate: dateOnly.optional(),
  endDate: dateOnly.nullable().optional(),

  // ✅ REQUIRED because DB column next_due_date is NOT NULL
  nextDueDate: dateOnly,

  rentAmount: z.number().positive().optional(),
  depositAmount: z.number().positive().optional(),

  status: tenancyStatusSchema.optional(),
  notes: z.string().max(5000).nullable().optional(),
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

  startDate: dateOnly.nullable().optional(),
  endDate: dateOnly.nullable().optional(),
  nextDueDate: dateOnly.nullable().optional(),

  rentAmount: z.number().positive().nullable().optional(),
  depositAmount: z.number().positive().nullable().optional(),

  notes: z.string().max(5000).nullable().optional(),
});
TS

# -----------------------------
# 2) Repo (matches DB column names)
# -----------------------------
cat > src/repos/tenancies.repo.ts <<'TS'
import type { PoolClient } from "pg";

export type TenancyStatus = "active" | "ended" | "terminated" | "pending_start";

export type TenancyRow = {
  id: string;
  listing_id: string;
  property_id: string;
  tenant_id: string;

  status: TenancyStatus | null;

  start_date: string | null;
  end_date: string | null;

  // ✅ NOT NULL in your DB
  next_due_date: string;

  rent_amount: string | null;
  security_deposit: string | null;

  created_at: string;
  updated_at: string;
};

export type InsertTenancyArgs = {
  listing_id: string;
  property_id: string;
  tenant_id: string;

  start_date?: string | null;
  end_date?: string | null;

  next_due_date: string; // REQUIRED

  rent_amount?: number | null;
  security_deposit?: number | null;

  status?: TenancyStatus | null;
};

export async function insertTenancy(client: PoolClient, data: InsertTenancyArgs): Promise<TenancyRow> {
  const { rows } = await client.query<TenancyRow>(
    `
    INSERT INTO tenancies (
      listing_id,
      property_id,
      tenant_id,
      status,
      start_date,
      end_date,
      next_due_date,
      rent_amount,
      security_deposit
    )
    VALUES (
      $1,$2,$3,
      COALESCE($4::tenancy_status, 'pending_start'::tenancy_status),
      $5::date,
      $6::date,
      $7::date,
      $8,
      $9
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
      data.next_due_date,
      data.rent_amount ?? null,
      data.security_deposit ?? null,
    ]
  );

  return rows[0]!;
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
  if (args.property_id) { where.push(`property_id = $${i++}`); params.push(args.property_id); }
  if (args.tenant_id) { where.push(`tenant_id = $${i++}`); params.push(args.tenant_id); }
  if (args.status) { where.push(`status = $${i++}::tenancy_status`); params.push(args.status); }

  params.push(args.limit); const limitIdx = i++;
  params.push(args.offset); const offsetIdx = i++;

  const { rows } = await client.query<TenancyRow>(
    `
    SELECT *
    FROM tenancies
    WHERE ${where.join(" AND ")}
    ORDER BY created_at DESC
    LIMIT $${limitIdx} OFFSET $${offsetIdx};
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
    next_due_date: string | null;
    rent_amount: number | null;
    security_deposit: number | null;
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
    UPDATE tenancies
    SET ${sets.join(", ")}
    WHERE id = $${i}
    RETURNING *;
    `,
    params
  );

  return rows[0] ?? null;
}
TS

# -----------------------------
# 3) Service
# -----------------------------
cat > src/services/tenancies.service.ts <<'TS'
import type { RlsContext } from "../db.js";
import { withRlsTransaction } from "../db.js";
import type { TenancyStatus } from "../repos/tenancies.repo.js";
import { insertTenancy, listTenancies, patchTenancy } from "../repos/tenancies.repo.js";

export async function createTenancy(
  ctx: RlsContext,
  data: {
    listing_id: string;
    property_id: string;
    tenant_id: string;

    start_date?: string | null;
    end_date?: string | null;

    next_due_date: string;

    rent_amount?: number | null;
    security_deposit?: number | null;

    status?: TenancyStatus | null;
  }
) {
  return withRlsTransaction(ctx, (client) => insertTenancy(client, data));
}

export async function getTenancies(
  ctx: RlsContext,
  args: {
    limit: number;
    offset: number;
    listing_id?: string;
    property_id?: string;
    tenant_id?: string;
    status?: TenancyStatus;
  }
) {
  return withRlsTransaction(ctx, (client) => listTenancies(client, args));
}

export async function updateTenancy(
  ctx: RlsContext,
  id: string,
  patch: Partial<{
    status: TenancyStatus | null;
    start_date: string | null;
    end_date: string | null;
    next_due_date: string | null;
    rent_amount: number | null;
    security_deposit: number | null;
  }>
) {
  return withRlsTransaction(ctx, (client) => patchTenancy(client, id, patch));
}
TS

# -----------------------------
# 4) Routes
# -----------------------------
cat > src/routes/tenancies.ts <<'TS'
import type { FastifyInstance } from "fastify";
import {
  createTenancyBodySchema,
  listTenanciesQuerySchema,
  patchTenancyBodySchema,
} from "../schemas/tenancies.schema.js";
import { createTenancy, getTenancies, updateTenancy } from "../services/tenancies.service.js";

export async function tenancyRoutes(app: FastifyInstance) {
  app.get("/v1/tenancies", { preHandler: [app.authenticate] }, async (req) => {
    const q = listTenanciesQuerySchema.parse((req as any).query ?? {});
    const ctx = (req as any).rls;

    const data = await getTenancies(ctx, {
      limit: q.limit,
      offset: q.offset,
      listing_id: q.listingId,
      property_id: q.propertyId,
      tenant_id: q.tenantId,
      status: q.status,
    });

    return { ok: true, data, paging: { limit: q.limit, offset: q.offset } };
  });

  app.post("/v1/tenancies", { preHandler: [app.authenticate] }, async (req) => {
    const body = createTenancyBodySchema.parse((req as any).body ?? {});
    const ctx = (req as any).rls;

    const row = await createTenancy(ctx, {
      listing_id: body.listingId,
      property_id: body.propertyId,
      tenant_id: body.tenantId,

      start_date: body.startDate ?? null,
      end_date: body.endDate ?? null,

      // ✅ maps to DB next_due_date NOT NULL
      next_due_date: body.nextDueDate,

      rent_amount: body.rentAmount ?? null,
      security_deposit: body.depositAmount ?? null,

      status: body.status ?? null,
    });

    return { ok: true, data: row };
  });

  app.patch("/v1/tenancies/:id", { preHandler: [app.authenticate] }, async (req) => {
    const body = patchTenancyBodySchema.parse((req as any).body ?? {});
    const params = (req as any).params as { id: string };
    const ctx = (req as any).rls;

    const row = await updateTenancy(ctx, params.id, {
      status: body.status ?? undefined,
      start_date: body.startDate ?? undefined,
      end_date: body.endDate ?? undefined,
      next_due_date: body.nextDueDate ?? undefined,
      rent_amount: body.rentAmount ?? undefined,
      security_deposit: body.depositAmount ?? undefined,
    });

    return { ok: true, data: row };
  });
}
TS

# -----------------------------
# 5) Test script (prints HTTP_CODE)
# -----------------------------
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
RESP="$(curl -s -w "\nHTTP_CODE:%{http_code}\n" -X POST "$API/v1/tenancies" \
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
  }")"

echo "$RESP" | sed '/^HTTP_CODE:/d' | jq || true
echo "$RESP" | grep '^HTTP_CODE:' || true

echo
echo "Listing tenancies..."
curl -s "$API/v1/tenancies?limit=10&offset=0" -H "authorization: Bearer $TOKEN" | jq

echo
echo "DB check: tenancies (last 5)"
PAGER=cat psql -d "$DB_NAME" -c "select id, listing_id, tenant_id, status, start_date, next_due_date, rent_amount, security_deposit, created_at from tenancies order by created_at desc limit 5;"
SH
chmod +x scripts/test_tenancies.sh

# -----------------------------
# 6) src/routes/index.ts — ensure import + register ONCE (no duplicates)
# -----------------------------
if [ -f src/routes/index.ts ]; then
  # remove duplicate imports
  perl -pi -e 'if(/^import\s+\{\s*tenancyRoutes\s*\}\s+from\s+"\.\/*tenancies\.js";\s*$/){ if($seen++){ $_="" } }' src/routes/index.ts

  # add import if missing
  if ! grep -q 'from "\.\/tenancies\.js"' src/routes/index.ts; then
    perl -0777 -pi -e 's/(import\s+\{\s*applicationRoutes\s*\}\s+from\s+"\.\/*applications\.js";\s*\n)/$1import { tenancyRoutes } from "\.\/tenancies\.js";\n/s' src/routes/index.ts \
    || perl -0777 -pi -e 's/(import\s+\{\s*listingRoutes\s*\}\s+from\s+"\.\/*listings\.js";\s*\n)/$1import { tenancyRoutes } from "\.\/tenancies\.js";\n/s' src/routes/index.ts \
    || perl -0777 -pi -e 's/(import\s+\{\s*propertyRoutes\s*\}\s+from\s+"\.\/*properties\.js";\s*\n)/$1import { tenancyRoutes } from "\.\/tenancies\.js";\n/s' src/routes/index.ts
  fi

  # remove ALL register lines then add ONE
  perl -pi -e 's/^\s*await\s+app\.register\(tenancyRoutes\);\s*$//g' src/routes/index.ts

  # insert register after applicationRoutes if present; else after listingRoutes; else after propertyRoutes
  if grep -q 'await app\.register\(applicationRoutes\);' src/routes/index.ts; then
    perl -0777 -pi -e 's/(await app\.register\(applicationRoutes\);\s*\n)/$1  await app.register(tenancyRoutes);\n/s' src/routes/index.ts
  elif grep -q 'await app\.register\(listingRoutes\);' src/routes/index.ts; then
    perl -0777 -pi -e 's/(await app\.register\(listingRoutes\);\s*\n)/$1  await app.register(tenancyRoutes);\n/s' src/routes/index.ts
  else
    perl -0777 -pi -e 's/(await app\.register\(propertyRoutes\);\s*\n)/$1  await app.register(tenancyRoutes);\n/s' src/routes/index.ts
  fi
fi

echo "✅ Tenancies repaired to match schema (next_due_date NOT NULL + proper mapping)."
echo "✅ Wrote:"
echo "  - src/schemas/tenancies.schema.ts"
echo "  - src/repos/tenancies.repo.ts"
echo "  - src/services/tenancies.service.ts"
echo "  - src/routes/tenancies.ts"
echo "  - scripts/test_tenancies.sh"
echo "✅ Cleaned: src/routes/index.ts (tenancyRoutes registered ONCE)"
echo
echo "Next:"
echo "  npm run dev"
echo "  ./scripts/test_tenancies.sh"
