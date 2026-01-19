#!/usr/bin/env bash
set -euo pipefail

# 1) Repo
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

export type CreateListingInput = {
  property_id: string;
  kind: string;

  // If omitted => DB default applies
  status?: string | null;

  created_by?: string | null; // normally current_user_uuid()
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
  data: CreateListingInput
): Promise<ListingRow> {
  // dynamic INSERT to avoid status=null overriding default
  const cols: string[] = [
    "organization_id",
    "property_id",
    "kind",
    // status optionally inserted
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

  const params: any[] = [];

  const addParam = (v: any) => {
    params.push(v);
    return `$${params.length}`;
  };

  const vals: string[] = [
    "current_organization_uuid()",
    addParam(data.property_id),
    addParam(data.kind),
    // status maybe inserted here
    "current_user_uuid()",
    addParam(data.agent_id ?? null),
    addParam(data.payee_user_id),
    addParam(data.base_price),
    addParam(data.listed_price),
    addParam(data.agent_commission_percent ?? null),
    addParam(data.requires_owner_approval ?? null),
    addParam(data.is_public ?? null),
    addParam(data.public_note ?? null),
  ];

  if (data.status !== undefined && data.status !== null) {
    cols.splice(3, 0, "status");
    vals.splice(3, 0, addParam(data.status));
  }

  const sql = `
    INSERT INTO property_listings (${cols.join(", ")})
    VALUES (${vals.join(", ")})
    RETURNING *
  `;

  const { rows } = await client.query<ListingRow>(sql, params);
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
    status: string | null;

    agent_id: string | null;
    payee_user_id: string | null;

    base_price: number;
    listed_price: number;

    agent_commission_percent: number | null;

    requires_owner_approval: boolean | null;
    owner_approved: boolean | null;
    owner_approved_at: string | null;
    owner_approved_by: string | null;

    is_public: boolean | null;
    public_note: string | null;
  }>
): Promise<ListingRow | null> {
  const sets: string[] = ["updated_at = now()"];
  const params: any[] = [];
  let i = 1;

  for (const [k, v] of Object.entries(patch)) {
    if (v === undefined) continue;
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

# 2) Service
cat > src/services/listings.service.ts <<'TS'
import type { PoolClient } from "pg";
import {
  insertListing,
  getListingById,
  listListings,
  patchListing,
  type ListingRow,
  type CreateListingInput,
} from "../repos/listings.repo.js";

export async function createListing(
  client: PoolClient,
  data: CreateListingInput
): Promise<ListingRow> {
  return insertListing(client, data);
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
  patch: Parameters<typeof patchListing>[2]
): Promise<ListingRow | null> {
  return patchListing(client, id, patch);
}
TS

# 3) Route
cat > src/routes/listings.ts <<'TS'
import type { FastifyInstance } from "fastify";
import type { PoolClient } from "pg";
import { withRlsTransaction } from "../config/database.js";
import { createListing, getListing, listAllListings, updateListing } from "../services/listings.service.js";

export async function listingRoutes(app: FastifyInstance) {
  // LIST
  app.get("/v1/listings", { preHandler: [app.authenticate] }, async (req) => {
    const q = req.query as any;
    const limit = Number(q.limit ?? 10);
    const offset = Number(q.offset ?? 0);

    const userId = req.user.sub;
    const orgId = req.user.org;

    const data = await withRlsTransaction({ userId, organizationId: orgId }, async (client: PoolClient) => {
      return listAllListings(client, { limit, offset });
    });

    return { ok: true, data, paging: { limit, offset } };
  });

  // GET ONE
  app.get("/v1/listings/:id", { preHandler: [app.authenticate] }, async (req) => {
    const { id } = req.params as any;
    const userId = req.user.sub;
    const orgId = req.user.org;

    const data = await withRlsTransaction({ userId, organizationId: orgId }, async (client: PoolClient) => {
      return getListing(client, id);
    });

    return { ok: true, data };
  });

  // CREATE
  app.post("/v1/listings", { preHandler: [app.authenticate] }, async (req) => {
    const body = req.body as any;

    const userId = req.user.sub;
    const orgId = req.user.org;

    const data = await withRlsTransaction({ userId, organizationId: orgId }, async (client: PoolClient) => {
      return createListing(client, {
        property_id: body.propertyId,
        kind: body.kind,

        // DO NOT pass status unless provided
        status: body.status ?? undefined,

        agent_id: body.agentId ?? null,
        payee_user_id: body.payeeUserId,

        base_price: body.basePrice,
        listed_price: body.listedPrice,

        agent_commission_percent: body.agentCommissionPercent ?? null,
        requires_owner_approval: body.requiresOwnerApproval ?? null,
        is_public: body.isPublic ?? null,
        public_note: body.publicNote ?? null,
      });
    });

    return { ok: true, data };
  });

  // PATCH
  app.patch("/v1/listings/:id", { preHandler: [app.authenticate] }, async (req) => {
    const { id } = req.params as any;
    const body = req.body as any;

    const userId = req.user.sub;
    const orgId = req.user.org;

    const data = await withRlsTransaction({ userId, organizationId: orgId }, async (client: PoolClient) => {
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
    });

    return { ok: true, data };
  });
}
TS

echo "✅ Fixed listings repo + service + route"
