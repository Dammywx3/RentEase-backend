import type { FastifyInstance } from "fastify";

export async function demoRoutes(app: FastifyInstance) {
  // Public demo
  app.get("/demo/public", async () => {
    return { ok: true, message: "Public demo route" };
  });

  // Protected demo (requires JWT)
  app.get(
    "/demo/protected",
    { preHandler: [app.authenticate] },
    async (req) => {
      return {
        ok: true,
        message: "Protected demo route",
        user: req.user,
      };
    }
  );
}
