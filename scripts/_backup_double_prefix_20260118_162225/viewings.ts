import type { FastifyInstance } from "fastify";
import type { PoolClient } from "pg";

import { withRlsTransaction } from "../db/rls_tx.js";

import { createViewing, getViewing, listAllViewings, updateViewing } from "../services/viewings.service.js";
import { createViewingBodySchema, listViewingsQuerySchema, patchViewingBodySchema } from "../schemas/viewings.schema.js";

function getCtx(req: any) {
  const userId = String(req?.user?.userId ?? "").trim();
  const organizationId = String(req?.orgId ?? "").trim();
  const role = (req?.user?.role ?? null) as any;
  return { userId, organizationId, role };
}

export async function viewingRoutes(app: FastifyInstance) {
  app.get("/viewings", { preHandler: [app.authenticate] }, async (req: any) => {
    const q = listViewingsQuerySchema.parse(req.query ?? {});
    const ctx = getCtx(req);

    const data = await withRlsTransaction(
      { userId: ctx.userId, organizationId: ctx.organizationId, role: ctx.role, eventNote: "viewings:list" },
      async (client: PoolClient) => {
        return listAllViewings(client, {
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

  app.get("/viewings/:id", { preHandler: [app.authenticate] }, async (req: any) => {
    const { id } = req.params as any;
    const ctx = getCtx(req);

    const data = await withRlsTransaction(
      { userId: ctx.userId, organizationId: ctx.organizationId, role: ctx.role, eventNote: `viewings:get:${String(id)}` },
      async (client: PoolClient) => {
        return getViewing(client, String(id));
      }
    );

    return { ok: true, data };
  });

  app.post("/viewings", { preHandler: [app.authenticate] }, async (req: any) => {
    const body = createViewingBodySchema.parse(req.body ?? {});
    const ctx = getCtx(req);

    const allowStatus = req.user?.role === "admin";
    const status = allowStatus ? (body.status ?? undefined) : undefined;

    const data = await withRlsTransaction(
      { userId: ctx.userId, organizationId: ctx.organizationId, role: ctx.role, eventNote: "viewings:create" },
      async (client: PoolClient) => {
        return createViewing(
          client,
          { userId: ctx.userId },
          {
            listing_id: body.listingId,
            property_id: body.propertyId,
            scheduled_at: body.scheduledAt,
            view_mode: body.viewMode ?? undefined,
            notes: body.notes ?? null,
            status,
          }
        );
      }
    );

    return { ok: true, data };
  });

  app.patch("/viewings/:id", { preHandler: [app.authenticate] }, async (req: any) => {
    const { id } = req.params as any;
    const body = patchViewingBodySchema.parse(req.body ?? {});
    const ctx = getCtx(req);

    const patch: any = {};
    if (body.scheduledAt !== undefined) patch.scheduled_at = body.scheduledAt;
    if (body.viewMode !== undefined) patch.view_mode = body.viewMode;
    if (body.notes !== undefined) patch.notes = body.notes;

    if (body.status !== undefined) {
      if (req.user?.role !== "admin") return { ok: false, error: "FORBIDDEN", message: "Only admin can change viewing status." };
      patch.status = body.status;
    }

    const data = await withRlsTransaction(
      { userId: ctx.userId, organizationId: ctx.organizationId, role: ctx.role, eventNote: `viewings:patch:${String(id)}` },
      async (client: PoolClient) => {
        return updateViewing(client, String(id), patch);
      }
    );

    return { ok: true, data };
  });
}
