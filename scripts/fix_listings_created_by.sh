#!/usr/bin/env bash
set -euo pipefail

mkdir -p src/repos src/services src/routes src/schemas scripts

# ----------------------------
# 1) Schema (validation shapes)
# ----------------------------
cat > src/schemas/listings.schema.ts <<'TS'
export type ListingKind = "owner_direct" | "agent_partner" | "agent_direct";
export type ListingStatus = "draft" | "active" | "paused" | "closed" | "archived";

export type CreateListingBody = {
  propertyId: string;
  kind: ListingKind;

  // only needed for agent_* kinds, enforced in route
  agentId?: string | null;

  // required by DB check constraint chk_listing_payee_present
  payeeUserId: string;

  basePrice: number;
  listedPrice: number;

  // optional
  status?: ListingStatus;
  agentCommissionPercent?: number | null;
  requiresOwnerApproval?: boolean | null;
  isPublic?: boolean | null;
  publicNote?: string | null;
};

export type PatchListingBody = Partial<{
  status: ListingStatus;
  agentId: string | null;
  payeeUserId: string;
  basePrice: number;
  listedPrice: number;
  agentCommissionPercent: number | null;
  requiresOwnerApproval: boolean | null;
  isPublic: boolean | null;
  publicNote: string | null;
}>;
TS

# ----------------------------
# 2) Repo (SQL)
# ----------------------------
cat > src/repos/listings.repo.ts <<'TS'
import type { PoolClient } from "pg";

export type ListingRow = {
  id: string;
  organization_id: string | null;
  property_id: string;
  kind: string;
  status: string | null;

  created_by: string | null;
  agent_id: string | null;
  payee_user_id: string | null;

  base_price: string;
  listed_price: string;

  agent_commission_percent: string | null;
  platform_fee_percent: string | null;
  platform_fee_basis: string | null;

  requires_owner_approval: boolean | null;
  owner_approved: boolean | null;
  owner_approved_at: string | null;
  owner_approved_by: string | null;

  is_public: boolean | null;
  public_note: string | null;

  created_at: string;
  updated_at: string;
  deleted_at: string | null;
};

type InsertListingInput = {
  property_id: string;
  kind: string;

  // IMPORTANT: omit status column if undefined, to let DB default 'draft' apply
  status?: string;

  agent_id?: string | null;
  payee_user_id: string;

  base_price: number;
  listed_price: number;

  agent_commission_percent?: number | null;
  requires_owner_approval?: boolean | null;
  is_public?: boolean | null;
  public_note?: string | null;
};

export async function insertListing(
  client: PoolClient,
  data: InsertListingInput
): Promise<ListingRow> {
  const cols: string[] = [
    "organization_id",
    "property_id",
    "kind",
    "created_by",
    "agent_id",
    "payee_user_id",
    "base_price",
    "listed_price",
    "agent_commission_percent",
    "requires_owner_approval",
    "is_public",
    "public_note",
  ];

  const vals: any[] = [
    // RLS helpers
    "current_organization_uuid()",
    data.property_id,
    data.kind,
    "current_user_uuid()",
    data.agent_id ?? null,
    data.payee_user_id,
    data.base_price,
    data.listed_price,
    data.agent_commission_percent ?? null,
    data.requires_owner_approval ?? null,
    data.is_public ?? null,
    data.public_note ?? null,
  ];

  // status: ONLY include if provided, else let default 'draft' apply
  if (typeof data.status !== "undefined") {
    cols.splice(3, 0, "status"); // after kind
    vals.splice(3, 0, data.status);
  }

  // Build SQL with placeholders, but allow "current_*_uuid()" as raw
  const placeholders: string[] = [];
  const params: any[] = [];
  let p = 1;

  for (const v of vals) {
    if (v === "current_organization_uuid()" || v === "current_user_uuid()") {
      placeholders.push(v);
    } else {
      placeholders.push(`$${p++}`);
      params.push(v);
    }
  }

  const { rows } = await client.query<ListingRow>(
    `
    INSERT INTO property_listings (${cols.join(", ")})
    VALUES (${placeholders.join(", ")})
    RETURNING *
    `,
    params
  );

  return rows[0]!;
}

export async function getListingById(
  client: PoolClient,
  id: string
): Promise<ListingRow | null> {
  const { rows } = await client.query<ListingRow>(
    `
    SELECT *
    FROM property_listings
    WHERE id = $1 AND deleted_at IS NULL
    LIMIT 1
    `,
    [id]
  );
  return rows[0] ?? null;
}

export async function listListings(
  client: PoolClient,
  args: { limit: number; offset: number }
): Promise<ListingRow[]> {
  const { rows } = await client.query<ListingRow>(
    `
    SELECT *
    FROM property_listings
    WHERE deleted_at IS NULL
    ORDER BY created_at DESC
    LIMIT $1 OFFSET $2
    `,
    [args.limit, args.offset]
  );
  return rows;
}

export async function patchListing(
  client: PoolClient,
  id: string,
  patch: Partial<{
    status: string;
    agent_id: string | null;
    payee_user_id: string;
    base_price: number;
    listed_price: number;
    agent_commission_percent: number | null;
    requires_owner_approval: boolean | null;
    is_public: boolean | null;
    public_note: string | null;
  }>
): Promise<ListingRow | null> {
  const sets: string[] = ["updated_at = now()"];
  const params: any[] = [];
  let i = 1;

  for (const [k, v] of Object.entries(patch)) {
    sets.push(`${k} = $${i++}`);
    params.push(v);
  }

  params.push(id);

  const { rows } = await client.query<ListingRow>(
    `
    UPDATE property_listings
    SET ${sets.join(", ")}
    WHERE id = $${i} AND deleted_at IS NULL
    RETURNING *
    `,
    params
  );

  return rows[0] ?? null;
}
TS

# ----------------------------
# 3) Service
# ----------------------------
cat > src/services/listings.service.ts <<'TS'
import type { PoolClient } from "pg";
import {
  insertListing,
  getListingById,
  listListings,
  patchListing,
  type ListingRow,
} from "../repos/listings.repo.js";

export async function createListing(
  client: PoolClient,
  input: {
    property_id: string;
    kind: string;
    status?: string;

    agent_id?: string | null;
    payee_user_id: string;

    base_price: number;
    listed_price: number;

    agent_commission_percent?: number | null;
    requires_owner_approval?: boolean | null;
    is_public?: boolean | null;
    public_note?: string | null;
  }
): Promise<ListingRow> {
  return insertListing(client, input);
}

export async function getListing(
  client: PoolClient,
  id: string
): Promise<ListingRow | null> {
  return getListingById(client, id);
}

export async function listAllListings(
  client: PoolClient,
  args: { limit: number; offset: number }
): Promise<ListingRow[]> {
  return listListings(client, args);
}

export async function updateListing(
  client: PoolClient,
  id: string,
  patch: Partial<{
    status: string;
    agent_id: string | null;
    payee_user_id: string;
    base_price: number;
    listed_price: number;
    agent_commission_percent: number | null;
    requires_owner_approval: boolean | null;
    is_public: boolean | null;
    public_note: string | null;
  }>
): Promise<ListingRow | null> {
  return patchListing(client, id, patch);
}
TS

# ----------------------------
# 4) Route (force correct IDs + validations)
# ----------------------------
cat > src/routes/listings.ts <<'TS'
import type { FastifyInstance } from "fastify";
import type { PoolClient } from "pg";
import { withRlsTransaction } from "../config/database.js";
import {
  createListing,
  getListing,
  listAllListings,
  updateListing,
} from "../services/listings.service.js";
import type { CreateListingBody, PatchListingBody } from "../schemas/listings.schema.js";

export async function listingRoutes(app: FastifyInstance) {
  // LIST
  app.get("/v1/listings", { preHandler: [app.authenticate] }, async (req) => {
    const q = req.query as any;
    const limit = Math.max(1, Math.min(100, Number(q.limit ?? 10)));
    const offset = Math.max(0, Number(q.offset ?? 0));

    const userId = req.user.sub;
    const orgId = req.user.org;

    const data = await withRlsTransaction(
      { userId, organizationId: orgId },
      async (client: PoolClient) => listAllListings(client, { limit, offset })
    );

    return { ok: true, data, paging: { limit, offset } };
  });

  // GET ONE
  app.get("/v1/listings/:id", { preHandler: [app.authenticate] }, async (req) => {
    const { id } = req.params as any;

    const userId = req.user.sub;
    const orgId = req.user.org;

    const data = await withRlsTransaction(
      { userId, organizationId: orgId },
      async (client: PoolClient) => getListing(client, id)
    );

    return { ok: true, data };
  });

  // CREATE
  app.post("/v1/listings", { preHandler: [app.authenticate] }, async (req, reply) => {
    const body = req.body as CreateListingBody;

    // app-level checks to avoid DB trigger errors
    if (!body.propertyId) return reply.code(400).send({ ok: false, message: "propertyId is required" });
    if (!body.kind) return reply.code(400).send({ ok: false, message: "kind is required" });
    if (!body.payeeUserId) return reply.code(400).send({ ok: false, message: "payeeUserId is required" });
    if (typeof body.basePrice !== "number" || body.basePrice <= 0) {
      return reply.code(400).send({ ok: false, message: "basePrice must be > 0" });
    }
    if (typeof body.listedPrice !== "number" || body.listedPrice <= 0) {
      return reply.code(400).send({ ok: false, message: "listedPrice must be > 0" });
    }

    // schema trigger expects agent_id for agent_direct (and usually agent_partner too)
    if ((body.kind === "agent_direct" || body.kind === "agent_partner") && !body.agentId) {
      return reply.code(400).send({ ok: false, message: `${body.kind} listing requires agentId` });
    }

    const userId = req.user.sub;
    const orgId = req.user.org;

    const data = await withRlsTransaction(
      { userId, organizationId: orgId },
      async (client: PoolClient) => {
        return createListing(client, {
          property_id: body.propertyId,
          kind: body.kind,

          // omit status if not provided so DB default 'draft' applies
          status: typeof body.status === "undefined" ? undefined : body.status,

          agent_id: body.agentId ?? null,
          payee_user_id: body.payeeUserId,

          base_price: body.basePrice,
          listed_price: body.listedPrice,

          agent_commission_percent: body.agentCommissionPercent ?? null,
          requires_owner_approval: body.requiresOwnerApproval ?? null,
          is_public: body.isPublic ?? null,
          public_note: body.publicNote ?? null,
        });
      }
    );

    return { ok: true, data };
  });

  // PATCH
  app.patch("/v1/listings/:id", { preHandler: [app.authenticate] }, async (req) => {
    const { id } = req.params as any;
    const body = req.body as PatchListingBody;

    const userId = req.user.sub;
    const orgId = req.user.org;

    const data = await withRlsTransaction(
      { userId, organizationId: orgId },
      async (client: PoolClient) => {
        return updateListing(client, id, {
          status: body.status ?? undefined,
          agent_id: body.agentId ?? undefined,
          payee_user_id: body.payeeUserId ?? undefined,
          base_price: body.basePrice ?? undefined,
          listed_price: body.listedPrice ?? undefined,
          agent_commission_percent: body.agentCommissionPercent ?? undefined,
          requires_owner_approval: body.requiresOwnerApproval ?? undefined,
          is_public: body.isPublic ?? undefined,
          public_note: body.publicNote ?? undefined,
        });
      }
    );

    return { ok: true, data };
  });
}
TS

# ----------------------------
# 5) Quick test script
# ----------------------------
cat > scripts/test_listings.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail

eval "$(./scripts/login.sh)" >/dev/null

echo "✅ TOKEN set"

PROPERTY_ID="$(curl -s "http://127.0.0.1:4000/v1/properties?limit=1&offset=0" \
  -H "authorization: Bearer $TOKEN" | jq -r '.data[0].id')"

ME_ID="$(curl -s http://127.0.0.1:4000/v1/me -H "authorization: Bearer $TOKEN" | jq -r '.data.id')"

echo "PROPERTY_ID=$PROPERTY_ID"
echo "ME_ID=$ME_ID"

curl -s -X POST http://127.0.0.1:4000/v1/listings \
  -H "content-type: application/json" \
  -H "authorization: Bearer $TOKEN" \
  -d "{
    \"propertyId\":\"$PROPERTY_ID\",
    \"kind\":\"agent_direct\",
    \"agentId\":\"$ME_ID\",
    \"payeeUserId\":\"$ME_ID\",
    \"basePrice\":1500,
    \"listedPrice\":1600,
    \"isPublic\": true
  }" | jq

echo
echo "DB check:"
psql -d rentease -c "select id, status, created_by, agent_id, payee_user_id from property_listings order by created_at desc limit 3;"
SH

chmod +x scripts/test_listings.sh

echo "✅ Fixed 5 files: listings.schema.ts, listings.repo.ts, listings.service.ts, listings.ts, test_listings.sh"
