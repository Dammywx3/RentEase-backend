import type { FastifyInstance } from "fastify";
import type { PoolClient } from "pg";

import { withRlsTransaction } from "../db/rls_tx.js";

import {
  createListing,
  getListing,
  listAllListings,
  updateListing,
} from "../services/listings.service.js";

import type { CreateListingBody, PatchListingBody } from "../schemas/listings.schema.js";

function getCtx(req: any) {
  const userId = String(req?.user?.userId ?? "").trim();
  const organizationId = String(req?.orgId ?? "").trim();
  const role = (req?.user?.role ?? null) as any;
  return { userId, organizationId, role };
}

export async function listingRoutes(app: FastifyInstance) {
  // LIST
  app.get("/", { preHandler: [app.authenticate] }, async (req: any) => {
    const q = req.query as any;
    const limit = Math.max(1, Math.min(100, Number(q.limit ?? 10)));
    const offset = Math.max(0, Number(q.offset ?? 0));

    const ctx = getCtx(req);

    const data = await withRlsTransaction(
      { userId: ctx.userId, organizationId: ctx.organizationId, role: ctx.role, eventNote: "listings:list" },
      async (client: PoolClient) => listAllListings(client, { limit, offset })
    );

    return { ok: true, data, paging: { limit, offset } };
  });

  // GET ONE
  app.get("/:id", { preHandler: [app.authenticate] }, async (req: any) => {
    const { id } = req.params as any;
    const ctx = getCtx(req);

    const data = await withRlsTransaction(
      { userId: ctx.userId, organizationId: ctx.organizationId, role: ctx.role, eventNote: `listings:get:${String(id)}` },
      async (client: PoolClient) => getListing(client, id)
    );

    return { ok: true, data };
  });

  // CREATE
  app.post("/", { preHandler: [app.authenticate] }, async (req: any, reply) => {
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

    const ctx = getCtx(req);

    const data = await withRlsTransaction(
      { userId: ctx.userId, organizationId: ctx.organizationId, role: ctx.role, eventNote: "listings:create" },
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
  app.patch("/:id", { preHandler: [app.authenticate] }, async (req: any) => {
    const { id } = req.params as any;
    const body = req.body as PatchListingBody;

    const ctx = getCtx(req);

    const data = await withRlsTransaction(
      { userId: ctx.userId, organizationId: ctx.organizationId, role: ctx.role, eventNote: `listings:patch:${String(id)}` },
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
