// src/routes/properties.ts
import type { FastifyInstance } from "fastify";

import {
  createPropertySchema,
  listPropertiesQuerySchema,
  patchPropertySchema,
} from "../schemas/properties.schema.js";

import {
  createPropertyForOrg,
  listPropertiesForOrg,
  getPropertyForOrg,
  patchPropertyForOrg,
} from "../services/properties.service.js";

function getCtx(req: any) {
  const userId = String(req?.user?.userId ?? "").trim();
  const organizationId = String(req?.orgId ?? "").trim();
  const role = String(req?.user?.role ?? "").trim() || null;

  if (!userId) throw new Error("Missing authenticated user id (req.user.userId)");
  if (!organizationId) throw new Error("Missing resolved organization id (req.orgId)");

  return { userId, organizationId, role };
}

export async function propertyRoutes(app: FastifyInstance) {
  // CREATE  ✅ POST /v1/properties
  app.post(
    "/",
    { preHandler: [app.authenticate] },
    async (req: any, reply) => {
      const parsed = createPropertySchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          ok: false,
          error: "VALIDATION_ERROR",
          issues: parsed.error.flatten(),
        });
      }

      const ctx = getCtx(req);

      const row = await createPropertyForOrg({
        userId: ctx.userId,
        organizationId: ctx.organizationId,
        input: parsed.data,
      });

      return reply.code(201).send({ ok: true, data: row });
    }
  );

  // LIST ✅ GET /v1/properties?limit=&offset=
  app.get(
    "/",
    { preHandler: [app.authenticate] },
    async (req: any, reply) => {
      const parsed = listPropertiesQuerySchema.safeParse(req.query);
      if (!parsed.success) {
        return reply.code(400).send({
          ok: false,
          error: "VALIDATION_ERROR",
          issues: parsed.error.flatten(),
        });
      }

      const ctx = getCtx(req);

      const rows = await listPropertiesForOrg({
        userId: ctx.userId,
        organizationId: ctx.organizationId,
        query: parsed.data,
      });

      return {
        ok: true,
        data: rows,
        paging: { limit: parsed.data.limit, offset: parsed.data.offset },
      };
    }
  );

  // GET BY ID ✅ GET /v1/properties/:id
  app.get(
    "/:id",
    { preHandler: [app.authenticate] },
    async (req: any, reply) => {
      const id = String((req.params as any).id ?? "").trim();
      if (!id) {
        return reply.code(400).send({ ok: false, error: "BAD_REQUEST", message: "Missing :id" });
      }

      const ctx = getCtx(req);

      const row = await getPropertyForOrg({
        userId: ctx.userId,
        organizationId: ctx.organizationId,
        propertyId: id,
      });

      if (!row) {
        return reply
          .code(404)
          .send({ ok: false, error: "NOT_FOUND", message: "Property not found" });
      }

      return { ok: true, data: row };
    }
  );

  // PATCH ✅ PATCH /v1/properties/:id
  app.patch(
    "/:id",
    { preHandler: [app.authenticate] },
    async (req: any, reply) => {
      const id = String((req.params as any).id ?? "").trim();
      if (!id) {
        return reply.code(400).send({ ok: false, error: "BAD_REQUEST", message: "Missing :id" });
      }

      const parsed = patchPropertySchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          ok: false,
          error: "VALIDATION_ERROR",
          issues: parsed.error.flatten(),
        });
      }

      const ctx = getCtx(req);

      const row = await patchPropertyForOrg({
        userId: ctx.userId,
        organizationId: ctx.organizationId,
        propertyId: id,
        patch: parsed.data,
      });

      if (!row) {
        return reply
          .code(404)
          .send({ ok: false, error: "NOT_FOUND", message: "Property not found" });
      }

      return { ok: true, data: row };
    }
  );
}