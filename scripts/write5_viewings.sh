#!/usr/bin/env bash
set -euo pipefail

mkdir -p src/schemas src/repos src/services src/routes scripts

cat > src/schemas/viewings.schema.ts <<'EOT'
import { z } from "zod";

export const viewingModeSchema = z.enum(["in_person", "virtual"]);
export const viewingStatusSchema = z.enum(["pending", "confirmed", "completed", "cancelled"]);

export const createViewingBodySchema = z.object({
  listingId: z.string().uuid(),
  propertyId: z.string().uuid(),
  scheduledAt: z.string().datetime({ offset: true }),
  viewMode: viewingModeSchema.optional(),
  notes: z.string().max(5000).optional(),
  status: viewingStatusSchema.optional(),
});

export const listViewingsQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(10),
  offset: z.coerce.number().int().min(0).default(0),
  listingId: z.string().uuid().optional(),
  propertyId: z.string().uuid().optional(),
  tenantId: z.string().uuid().optional(),
  status: viewingStatusSchema.optional(),
});

export const patchViewingBodySchema = z.object({
  scheduledAt: z.string().datetime({ offset: true }).optional(),
  viewMode: viewingModeSchema.optional(),
  notes: z.string().max(5000).nullable().optional(),
  status: viewingStatusSchema.optional(),
});
EOT

cat > src/repos/viewings.repo.ts <<'EOT'
import type { Poollient } from "pg";

export type ViewingRow = {
  id: string;
  listing_id: string;
  property_id: string;
  tenant_id: string;
  scheduled_at: string;
  view_mode: "in_person" | "virtual" | null;
  status: "pending" | "confirmed" | "completed" | "cancelled" | null;
  notes: string | null;
  created_at: string;
  updated_at: string;
};

export async function insertViewing(
  client: PoolClient,
  data: {
    listing_id: string;
    property_id: string;
    tenant_id: string;
    scheduled_at: string;
    view_mode?: ViewingRow["view_mode"];
    status?: ViewingRow["status"];
    notes?: string | null;
  }
): Promise<ViewingRow> {
  const { rows } = await client.query<ViewingRow>(
    `
    INSERT INTO property_viewings (
      listing_id, property_id, tenant_id,
      scheduled_at, view_mode, status, notes
    )
    VALUES (
      $1,$2,$3,
      $4::timestamptz,
      COALESCE($5, 'in_person'::viewing_mode),
      COALESCE($6, 'pending'::viewing_status),
      $7
    )
    RETURNING *;
    `,
    [
      data.listing_id,
      data.property_id,
      data.tenant_id,
      data.scheduled_at,
      data.view_mode ?? null,
      data.status ?? null,
      data.notes ?? null,
    ]
  );
  return rows[0]!;
}

export async function getViewingById(client: PoolClient, id: string): Promise<ViewingRow | null> {
  const { rows } = await client.query<ViewingRow>(`SELECT * FROM property_viewings WHERE id=$1 LIMIT 1`, [id]);
  return rows[0] ?? null;
}

export async function listViewings(
  client: PoolClient,
  args: { limit: number; offset: number; listing_id?: string; property_id?: string; tenant_id?: string; status?: ViewingRow["status"]; }
): Promise<ViewingRow[]> {
  const where: string[] = ["1=1"];
  const params: any[] = [];
  let i = 1;

  if (args.listing_id) { where.push(`listing_id = $${i++}`); params.push(args.listing_id); }
  if (args.property_id) { where.push(`property_id = $${i++}`); params.push(args.property_id); }
  if (args.tenant_id) { where.push(`tenant_id = $${i++}`); params.push(args.tenant_id); }
  if (args.status) { where.push(`status = $${i++}`); params.push(args.status); }

  params.push(args.limit); const limitIdx = i++;
  params.push(args.offset); const offsetIdx = i++;

  const { rows } = await client.query<ViewingRow>(
    `
    SELECT *
    FROM property_viewings
    WHERE ${where.join(" AND ")}
    ORDER BY scheduled_at DESC
    LIMIT $${limitIdx} OFFSET $${offsetIdx}
    `,
    params
  );
  return rows;
}

export async function patchViewing(
  client: PoolClient,
  id: string,
  patch: Partial<{ scheduled_at: string; view_mode: ViewingRow["view_mode"]; status: ViewingRow["status"]; notes: string | null; }>
): Promise<ViewingRow | null> {
  const sets: string[] = ["updated_at = now()"];
  const params: any[] = [];
  let i = 1;

  for (const [k, v] of Object.entries(patch)) {
    if (k === "scheduled_at") { sets.push(`${k} = $${i++}::timestamptz`); params.push(v); continue; }
    sets.push(`${k} = $${i++}`);
    params.push(v);
  }
  params.push(id);

  const { rows } = await client.query<ViewingRow>(
    `UPDATE property_viewings SET ${sets.join(", ")} WHERE id = $${i} RETURNING *`,
    params
  );
  return rows[0] ?? null;
}
EOT

cat > src/services/viewings.service.ts <<'EOT'
import type { PoolClient } from "pg";
import { insertViewing, getViewingById, listViewings, patchViewing, type ViewingRow } from "../repos/viewings.repo.js";

export async function createViewing(
  client: PoolClient,
  ctx: { userId: string },
  data: { listing_id: string; property_id: string; scheduled_at: string; view_mode?: ViewingRow["view_mode"]; status?: ViewingRow["status"]; notes?: string | null; }
) {
  return insertViewing(client, {
    listing_id: data.listing_id,
    property_id: data.property_id,
    tenant_id: ctx.userId,
    scheduled_at: data.scheduled_at,
    view_mode: data.view_mode,
    status: data.status,
    notes: data.notes ?? null,
  });
}

export async function getViewing(client: PoolClient, id: string) {
  return getViewingById(client, id);
}

export async function listAllViewings(
  client: PoolClient,
  args: { limit: number; offset: number; listing_id?: string; property_id?: string; tenant_id?: string; status?: ViewingRow["status"]; }
) {
  return listViewings(client, args);
}

export async function updateViewing(
  client: PoolClient,
  id: string,
  patch: Partial<{ scheduled_at: string; view_mode: ViewingRow["view_mode"]; status: ViewingRow["status"]; notes: string | null; }>
) {
  return patchViewing(client, id, patch);
}
EOT

cat > src/routes/viewings.ts <<'EOT'
import type { FastifyInstance } from "fastify";
import type { PoolClient } from "pg";
import { withRlsTransaction } from "../config/database.js";

import { createViewing, getViewing, listAllViewings, updateViewing } from "../services/viewings.service.js";
import { createViewingBodySchema, listViewingsQuerySchema, patchViewingBodySchema } from "../schemas/viewings.schema.js";

export async function viewingRoutes(app: FastifyInstance) {
  app.get("/v1/viewings", { preHandler: [app.authenticate] }, async (req) => {
    const q = listViewingsQuerySchema.parse(req.query ?? {});
    const userId = req.user.sub;
    const orgId = req.user.org;

    const data = await withRlsTransaction({ userId, organizationId: orgId }, async (client: PoolClient) => {
      return listAllViewings(client, {
        limit: q.limit,
        offset: q.offset,
        listing_id: q.listingId,
        property_id: q.propertyId,
        tenant_id: q.tenantId,
        status: q.status ?? undefined,
      });
    });

    return { ok: true, data, paging: { limit: q.limit, offset: q.offset } };
  });

  app.get("/v1/viewings/:id", { preHandler: [app.authenticate] }, async (req) => {
    const { id } = req.params as any;
    const userId = req.user.sub;
    const orgId = req.user.org;

    const data = await withRlsTransaction({ userId, organizationId: orgId }, async (client: PoolClient) => {
      return getViewing(client, String(id));
    });

    return { ok: true, data };
  });

  app.post("/v1/viewings", { preHandler: [app.authenticate] }, async (req) => {
    const body = createViewingBodySchema.parse(req.body ?? {});
    const userId = req.user.sub;
    const orgId = req.user.org;

    const allowStatus = req.user.role === "admin";
    const status = allowStatus ? (body.status ?? undefined) : undefined;

    const data = await withRlsTransaction({ userId, organizationId: orgId }, async (client: PoolClient) => {
      return createViewing(client, { userId }, {
        listing_id: body.listingId,
        property_id: body.propertyId,
        scheduled_at: body.scheduledAt,
        view_mode: body.viewMode ?? undefined,
        notes: body.notes ?? null,
        status,
      });
    });

    return { ok: true, data };
  });

  app.patch("/v1/viewings/:id", { preHandler: [app.authenticate] }, async (req) => {
    const { id } = req.params as any;
    const body = patchViewingBodySchema.parse(req.body ?? {});
    const userId = req.user.sub;
    const orgId = req.user.org;

    const patch: any = {};
    if (body.scheduledAt !== undefined) patch.scheduled_at = body.scheduledAt;
    if (body.viewMode !== undefined) patch.view_mode = body.viewMode;
    if (body.notes !== undefined) patch.notes = body.notes;

    if (body.status !== undefined) {
      if (req.user.role !== "admin") return { ok: false, error: "FORBIDDEN", message: "Only admin can change viewing status." };
      patch.status = body.status;
    }

    const data = await withRlsTransaction({ userId, organizationId: orgId }, async (client: PoolClient) => {
      return updateViewing(client, String(id), patch);
    });

    return { ok: true, data };
  });
}
EOT

cat > scripts/test_viewings.sh <<'EOT'
#!/usr/bin/env bash
set -euo pipefail

API="http://127.0.0.1:4000"

eval "$(./scripts/login.sh)"
echo "✅ TOKEN set"

ME_ID="$(curl -s $API/v1/me -H "authorization: Bearer $TOKEN" | jq -r '.data.id')"
PROPERTY_ID="$(curl -s "$API/v1/properties?limit=1&offset=0" -H "authorization: Bearer $TOKEN" | jq -r '.data[0].id')"
LISTING_ID="$(curl -s "$API/v1/listings?limit=1&offset=0" -H "authorization: Bearer $TOKEN" | jq -r '.data[0].id')"

echo "ME_ID=$ME_ID"
echo "PROPERTY_ID=$PROPERTY_ID"
echo "LISTING_ID=$LISTING_ID"

echo
echo "Creating viewing..."
curl -s -X POST "$API/v1/viewings" \
  -H "content-type: application/json" \
  -H "authorization: Bearer $TOKEN" \
  -d "{
    \"listingId\":\"$LISTING_ID\",
    \"propertyId\":\"$PROPERTY_ID\",
    \"scheduledAt\":\"2026-02-05T10:00:00Z\",
    \"viewMode\":\"in_person\",
    \"notes\":\"First viewing\"
  }" | jq

echo
echo "Listing viewings..."
curl -s "$API/v1/viewings?limit=10&offset=0" \
  -H "authorization: Bearer $TOKEN" | jq

echo
echo "DB check: property_viewings (last 5)"
PAGER=cat psql -d rentease -c "select id, listing_id, tenant_id, scheduled_at, view_mode, status, created_at from property_viewings order by created_at desc limit 5;"
EOT
chmod +x scripts/test_viewings.sh

# Update src/routes/index.ts (import + register)
if [ -f src/routes/index.ts ]; then
  if ! grep -q 'from "\.\/viewings\.js"' src/routes/index.ts; then
    perl -0777 -pi -e 's/(import\s+\{\s*propertyRoutes\s*\}\s+from\s+"\.\/properties\.js";\s*\n)/$1import { viewingRoutes } from "\.\/viewings\.js";\n/s' src/routes/index.ts
  fi
  if ! grep -q 'app\.register\(viewingRoutes\)' src/routes/index.ts; then
    perl -0777 -pi -e 's/(await app\.register\(propertyRoutes\);\s*\n)/$1  await app.register(viewingRoutes);\n/s' src/routes/index.ts
  fi
fi

echo "✅ Wrote 5 files: viewings.schema.ts, viewings.repo.ts, viewings.service.ts, viewings.ts, test_viewings.sh"
echo "✅ Updated: src/routes/index.ts (import + register viewingRoutes)"
echo
echo "Next:"
echo "  npm run dev"
echo "  ./scripts/test_viewings.sh"
