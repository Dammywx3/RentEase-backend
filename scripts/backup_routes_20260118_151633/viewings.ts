import type { FastifyInstance } from "fastify";
import type { PoolClient } from "pg";
import { withRlsTransaction } from "../config/database.js";

import { createViewing, getViewing, listAllViewings, updateViewing } from "../services/viewings.service.js";
import { createViewingBodySchema, listViewingsQuerySchema, patchViewingBodySchema } from "../schemas/viewings.schema.js";

export async function viewingRoutes(app: FastifyInstance) {
  app.get("/viewings", { preHandler: [app.authenticate] }, async (req) => {
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

  app.get("/viewings/:id", { preHandler: [app.authenticate] }, async (req) => {
    const { id } = req.params as any;
    const userId = req.user.sub;
    const orgId = req.user.org;

    const data = await withRlsTransaction({ userId, organizationId: orgId }, async (client: PoolClient) => {
      return getViewing(client, String(id));
    });

    return { ok: true, data };
  });

  app.post("/viewings", { preHandler: [app.authenticate] }, async (req) => {
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

  app.patch("/viewings/:id", { preHandler: [app.authenticate] }, async (req) => {
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
