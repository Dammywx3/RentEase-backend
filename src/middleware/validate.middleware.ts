import type { FastifyRequest } from "fastify";
import type { ZodTypeAny } from "zod";

type Schemas = {
  body?: ZodTypeAny;
  query?: ZodTypeAny;
  params?: ZodTypeAny;
};

/**
 * Usage:
 * app.post("/path", { preHandler: validate({ body: schema }) }, async (req) => ...)
 */
export function validate(schemas: Schemas) {
  return async (req: FastifyRequest) => {
    if (schemas.body) {
      const parsed = schemas.body.safeParse((req as any).body);
      if (!parsed.success) {
        const err: any = new Error("Validation error");
        err.statusCode = 400;
        err.code = "VALIDATION_ERROR";
        err.details = parsed.error.flatten();
        throw err;
      }
      (req as any).body = parsed.data;
    }

    if (schemas.query) {
      const parsed = schemas.query.safeParse((req as any).query);
      if (!parsed.success) {
        const err: any = new Error("Validation error");
        err.statusCode = 400;
        err.code = "VALIDATION_ERROR";
        err.details = parsed.error.flatten();
        throw err;
      }
      (req as any).query = parsed.data;
    }

    if (schemas.params) {
      const parsed = schemas.params.safeParse((req as any).params);
      if (!parsed.success) {
        const err: any = new Error("Validation error");
        err.statusCode = 400;
        err.code = "VALIDATION_ERROR";
        err.details = parsed.error.flatten();
        throw err;
      }
      (req as any).params = parsed.data;
    }
  };
}
