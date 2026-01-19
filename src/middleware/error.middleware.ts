import type { FastifyInstance } from "fastify";

export function registerErrorHandler(app: FastifyInstance) {
  app.setErrorHandler(async (err, req, reply) => {
    req.log.error({ err }, "Unhandled error");

    const status =
      (err as any).statusCode ||
      (err as any).status ||
      500;

    return reply.status(status).send({
      ok: false,
      error: (err as any).code || "INTERNAL_ERROR",
      message: (err as any).message || "Something went wrong",
    });
  });
}
