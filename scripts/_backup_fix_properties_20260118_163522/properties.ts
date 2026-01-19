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

export async function propertyRoutes(app: FastifyInstance) {
  // CREATE
  app.get("/",
    { preHandler: [app.authenticate] },
    async (req, reply) => {
      const parsed = createPropertySchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          ok: false,
          error: "VALIDATION_ERROR",
          issues: parsed.error.flatten(),
        });
      }

      const userId = req.user.sub;
      const organizationId = req.user.org;

      const row = await createPropertyForOrg({
        userId,
        organizationId,
        input: parsed.data,
      });

      return reply.code(201).send({ ok: true, data: row });
    }
  );

  // LIST
  app.get("/",
    { preHandler: [app.authenticate] },
    async (req, reply) => {
      const parsed = listPropertiesQuerySchema.safeParse(req.query);
      if (!parsed.success) {
        return reply.code(400).send({
          ok: false,
          error: "VALIDATION_ERROR",
          issues: parsed.error.flatten(),
        });
      }

      const userId = req.user.sub;
      const organizationId = req.user.org;

      const rows = await listPropertiesForOrg({
        userId,
        organizationId,
        query: parsed.data,
      });

      return {
        ok: true,
        data: rows,
        paging: { limit: parsed.data.limit, offset: parsed.data.offset },
      };
    }
  );

  // GET BY ID
  app.get("/:id",
    { preHandler: [app.authenticate] },
    async (req, reply) => {
      const id = (req.params as any).id as string;

      const userId = req.user.sub;
      const organizationId = req.user.org;

      const row = await getPropertyForOrg({
        userId,
        organizationId,
        propertyId: id,
      });

      if (!row) {
        return reply.code(404).send({ ok: false, error: "NOT_FOUND", message: "Property not found" });
      }

      return { ok: true, data: row };
    }
  );

  // PATCH
  app.patch("/:id",
    { preHandler: [app.authenticate] },
    async (req, reply) => {
      const id = (req.params as any).id as string;

      const parsed = patchPropertySchema.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({
          ok: false,
          error: "VALIDATION_ERROR",
          issues: parsed.error.flatten(),
        });
      }

      const userId = req.user.sub;
      const organizationId = req.user.org;

      const row = await patchPropertyForOrg({
        userId,
        organizationId,
        propertyId: id,
        patch: parsed.data,
      });

      if (!row) {
        return reply.code(404).send({ ok: false, error: "NOT_FOUND", message: "Property not found" });
      }

      return { ok: true, data: row };
    }
  );
}
