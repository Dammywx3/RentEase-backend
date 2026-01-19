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
  app.get("/listings", { preHandler: [app.authenticate] }, async (req) => {
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
  app.get("/listings/:id", { preHandler: [app.authenticate] }, async (req) => {
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
  app.post("/listings", { preHandler: [app.authenticate] }, async (req, reply) => {
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
  app.patch("/listings/:id", { preHandler: [app.authenticate] }, async (req) => {
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
