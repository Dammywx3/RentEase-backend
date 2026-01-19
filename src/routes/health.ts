import { FastifyInstance } from "fastify";

export async function healthRoutes(app: FastifyInstance) {
  app.get("/health", async () => {
    return { ok: true, service: "RentEase API", time: new Date().toISOString() };
  });
}