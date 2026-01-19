#!/usr/bin/env bash
set -euo pipefail

mkdir -p src/schemas src/repos src/services src/routes scripts

# -------------------------------
# 1) src/schemas/listings.schema.ts
# -------------------------------
cat > src/schemas/listings.schema.ts <<'EOT'
import { z } from "zod";

export const ListListingsQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(10),
  offset: z.coerce.number().int().min(0).default(0),
  status: z.string().optional(),
  kind: z.string().optional(),
  isPublic: z.coerce.boolean().optional(),
  propertyId: z.string().uuid().optional(),
});

export const CreateListingBodySchema = z.object({
  propertyId: z.string().uuid(),
  kind: z.string(), // listing_kind enum in DB
  basePrice: z.coerce.number().positive(),
  listedPrice: z.coerce.number().positive(),

  // optional fields
  status: z.string().optional(), // listing_status enum
  agentId: z.string().uuid().nullable().optional(),
  payeeUserId: z.string().uuid().nullable().optional(),

  agentCommissionPercent: z.coerce.number().min(0).max(100).optional(),
  requiresOwnerApproval: z.coerce.boolean().optional(),
  isPublic: z.coerce.boolean().optional(),
  publicNote: z.string().max(5000).nullable().optional(),
});

export const PatchListingBodySchema = z.object({
  status: z.string().optional(),
  listedPrice: z.coerce.number().positive().optional(),
  agentId: z.string().uuid().nullable().optional(),
  payeeUserId: z.string().uuid().nullable().optional(),

  agentCommissionPercent: z.coerce.number().min(0).max(100).optional(),
  requiresOwnerApproval: z.coerce.boolean().optional(),
  ownerApproved: z.coerce.boolean().optional(),
  ownerApprovedAt: z.string().datetime().nullable().optional(),
  ownerApprovedBy: z.string().uuid().nullable().optional(),

  isPublic: z.coerce.boolean().optional(),
  publicNote: z.string().max(5000).nullable().optional(),
}).strict();
EOT

# -------------------------------
# 2) src/repos/listings.repo.ts
# -------------------------------
cat > src/repos/listings.repo.ts <<'EOT'
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

  base_price: string;    // numeric -> string
  listed_price: string;  // numeric -> string

  agent_commission_percent: string | null; // numeric -> string
  platform_fee_percent: string | null;     // numeric -> string
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

export async function insertListing(
  client: PoolClient,
  data: {
    organization_id: string;
    property_id: string;
    kind: string;

    base_price: number;
    listed_price: number;

    status?: string | null;
    created_by?: string | null;
    agent_id?: string | null;
    payee_user_id?: string | null;

    agent_commission_percent?: number | null;
    requires_owner_approval?: boolean | null;
    is_public?: boolean | null;
    public_note?: string | null;
  }
): Promise<ListingRow> {
  const { rows } = await client.query<ListingRow>(
    `
    INSERT INTO property_listings (
      organization_id,
      property_id,
      kind,
      status,
      created_by,
      agent_id,
      payee_user_id,
      base_price,
      listed_price,
      agent_commission_percent,
      requires_owner_approval,
      is_public,
      public_note
    )
    VALUES (
      $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13
    )
    RETURNING *
    `,
    [
      data.organization_id,
      data.property_id,
      data.kind,
      data.status ?? null,
      data.created_by ?? null,
      data.agent_id ?? null,
      data.payee_user_id ?? null,
      data.base_price,
      data.listed_price,
      data.agent_commission_percent ?? null,
      data.requires_owner_approval ?? null,
      data.is_public ?? null,
      data.public_note ?? null,
    ]
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
  args: {
    limit: number;
    offset: number;
    status?: string;
    kind?: string;
    is_public?: boolean;
    property_id?: string;
  }
): Promise<ListingRow[]> {
  const where: string[] = ["deleted_at IS NULL"];
  const params: any[] = [];
  let i = 1;

  if (args.status) {
    where.push(`status = $${i++}`);
    params.push(args.status);
  }
  if (args.kind) {
    where.push(`kind = $${i++}`);
    params.push(args.kind);
  }
  if (typeof args.is_public === "boolean") {
    where.push(`is_public = $${i++}`);
    params.push(args.is_public);
  }
  if (args.property_id) {
    where.push(`property_id = $${i++}`);
    params.push(args.property_id);
  }

  params.push(args.limit);
  const limitIdx = i++;
  params.push(args.offset);
  const offsetIdx = i++;

  const { rows } = await client.query<ListingRow>(
    `
    SELECT *
    FROM property_listings
    WHERE ${where.join(" AND ")}
    ORDER BY created_at DESC
    LIMIT $${limitIdx} OFFSET $${offsetIdx}
    `,
    params
  );

  return rows;
}

export async function patchListing(
  client: PoolClient,
  id: string,
  patch: Partial<{
    status: string | null;
    listed_price: number;
    agent_id: string | null;
    payee_user_id: string | null;

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
EOT

# -------------------------------
# 3) src/services/listings.service.ts
# -------------------------------
cat > src/services/listings.service.ts <<'EOT'
import { withRlsTransaction } from "../config/database.js";
import {
  getListingById,
  insertListing,
  listListings,
  patchListing,
} from "../repos/listings.repo.js";

export async function createListingService(ctx: { userId: string; organizationId: string }, body: {
  propertyId: string;
  kind: string;
  basePrice: number;
  listedPrice: number;

  status?: string;
  agentId?: string | null;
  payeeUserId?: string | null;

  agentCommissionPercent?: number;
  requiresOwnerApproval?: boolean;
  isPublic?: boolean;
  publicNote?: string | null;
}) {
  return withRlsTransaction(
    { userId: ctx.userId, organizationId: ctx.organizationId },
    async (client) => {
      // NOTE: Your RLS policy is strict here.
      // - owner_direct: property.owner_id must be current_user_uuid()
      // - agent_*: current user must be agent role, etc.
      // Admin can bypass via is_admin().
      const row = await insertListing(client, {
        organization_id: ctx.organizationId,
        property_id: body.propertyId,
        kind: body.kind,

        base_price: body.basePrice,
        listed_price: body.listedPrice,

        status: body.status ?? null,
        created_by: ctx.userId,

        agent_id: body.agentId ?? null,
        payee_user_id: (body.payeeUserId ?? ctx.userId) ?? null,

        agent_commission_percent: body.agentCommissionPercent ?? null,
        requires_owner_approval: body.requiresOwnerApproval ?? null,
        is_public: body.isPublic ?? null,
        public_note: body.publicNote ?? null,
      });

      return row;
    }
  );
}

export async function getListingService(ctx: { userId: string; organizationId: string }, id: string) {
  return withRlsTransaction(
    { userId: ctx.userId, organizationId: ctx.organizationId },
    async (client) => getListingById(client, id)
  );
}

export async function listListingsService(ctx: { userId: string; organizationId: string }, args: {
  limit: number;
  offset: number;
  status?: string;
  kind?: string;
  isPublic?: boolean;
  propertyId?: string;
}) {
  return withRlsTransaction(
    { userId: ctx.userId, organizationId: ctx.organizationId },
    async (client) =>
      listListings(client, {
        limit: args.limit,
        offset: args.offset,
        status: args.status,
        kind: args.kind,
        is_public: args.isPublic,
        property_id: args.propertyId,
      })
  );
}

export async function patchListingService(ctx: { userId: string; organizationId: string }, id: string, patch: any) {
  return withRlsTransaction(
    { userId: ctx.userId, organizationId: ctx.organizationId },
    async (client) => patchListing(client, id, patch)
  );
}
EOT

# -------------------------------
# 4) src/routes/listings.ts
# -------------------------------
cat > src/routes/listings.ts <<'EOT'
import type { FastifyInstance } from "fastify";
import { CreateListingBodySchema, ListListingsQuerySchema, PatchListingBodySchema } from "../schemas/listings.schema.js";
import { createListingService, getListingService, listListingsService, patchListingService } from "../services/listings.service.js";

export async function listingRoutes(app: FastifyInstance) {
  // Create listing
  app.post("/v1/listings", { preHandler: [app.authenticate] }, async (req: any, reply) => {
    const body = CreateListingBodySchema.parse(req.body);

    const userId = req.user.sub as string;
    const organizationId = req.user.org as string;

    const data = await createListingService(
      { userId, organizationId },
      {
        propertyId: body.propertyId,
        kind: body.kind,
        basePrice: body.basePrice,
        listedPrice: body.listedPrice,

        status: body.status,
        agentId: body.agentId ?? null,
        payeeUserId: body.payeeUserId ?? null,

        agentCommissionPercent: body.agentCommissionPercent,
        requiresOwnerApproval: body.requiresOwnerApproval,
        isPublic: body.isPublic,
        publicNote: body.publicNote ?? null,
      }
    );

    return reply.code(201).send({ ok: true, data });
  });

  // List listings
  app.get("/v1/listings", { preHandler: [app.authenticate] }, async (req: any) => {
    const q = ListListingsQuerySchema.parse(req.query);

    const userId = req.user.sub as string;
    const organizationId = req.user.org as string;

    const data = await listListingsService(
      { userId, organizationId },
      {
        limit: q.limit,
        offset: q.offset,
        status: q.status,
        kind: q.kind,
        isPublic: q.isPublic,
        propertyId: q.propertyId,
      }
    );

    return { ok: true, data, paging: { limit: q.limit, offset: q.offset } };
  });

  // Get listing by id
  app.get("/v1/listings/:id", { preHandler: [app.authenticate] }, async (req: any) => {
    const id = String(req.params.id);
    const userId = req.user.sub as string;
    const organizationId = req.user.org as string;

    const data = await getListingService({ userId, organizationId }, id);
    return { ok: true, data };
  });

  // Patch listing
  app.patch("/v1/listings/:id", { preHandler: [app.authenticate] }, async (req: any) => {
    const id = String(req.params.id);
    const patch = PatchListingBodySchema.parse(req.body);

    const userId = req.user.sub as string;
    const organizationId = req.user.org as string;

    // map camelCase -> db snake_case where needed
    const dbPatch: any = {};
    if (patch.status !== undefined) dbPatch.status = patch.status;
    if (patch.listedPrice !== undefined) dbPatch.listed_price = patch.listedPrice;
    if (patch.agentId !== undefined) dbPatch.agent_id = patch.agentId;
    if (patch.payeeUserId !== undefined) dbPatch.payee_user_id = patch.payeeUserId;

    if (patch.agentCommissionPercent !== undefined) dbPatch.agent_commission_percent = patch.agentCommissionPercent;
    if (patch.requiresOwnerApproval !== undefined) dbPatch.requires_owner_approval = patch.requiresOwnerApproval;

    if (patch.ownerApproved !== undefined) dbPatch.owner_approved = patch.ownerApproved;
    if (patch.ownerApprovedAt !== undefined) dbPatch.owner_approved_at = patch.ownerApprovedAt;
    if (patch.ownerApprovedBy !== undefined) dbPatch.owner_approved_by = patch.ownerApprovedBy;

    if (patch.isPublic !== undefined) dbPatch.is_public = patch.isPublic;
    if (patch.publicNote !== undefined) dbPatch.public_note = patch.publicNote;

    const data = await patchListingService({ userId, organizationId }, id, dbPatch);
    return { ok: true, data };
  });
}
EOT

# -------------------------------
# 5) src/routes/index.ts (update to register listingRoutes)
# -------------------------------
cat > src/routes/index.ts <<'EOT'
import type { FastifyInstance } from "fastify";

import { healthRoutes } from "./health.js";
import { demoRoutes } from "./demo.js";
import { meRoutes } from "./me.js";
import { organizationRoutes } from "./organizations.js";
import { authRoutes } from "./auth.js";
import { propertyRoutes } from "./properties.js";
import { listingRoutes } from "./listings.js";

export async function registerRoutes(app: FastifyInstance) {
  await app.register(healthRoutes);
  await app.register(demoRoutes);

  await app.register(authRoutes);
  await app.register(meRoutes);

  await app.register(organizationRoutes);
  await app.register(propertyRoutes);
  await app.register(listingRoutes);
}
EOT

echo "✅ Wrote 5 files: listings.schema.ts, listings.repo.ts, listings.service.ts, listings.ts, routes/index.ts"
