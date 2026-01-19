// src/api/middleware/rlsContext.middleware.ts
import type { FastifyReply, FastifyRequest } from "fastify";
import type { JwtPayload } from "../plugins/jwt.js";

export async function rlsContextPreHandler(
  req: FastifyRequest,
  reply: FastifyReply
) {
  const user = req.user as JwtPayload | undefined;

  if (!user?.sub || !user?.org) {
    return reply.code(400).send({
      ok: false,
      error: "RLS_CONTEXT_MISSING",
      message: "userId/orgId missing from auth token",
    });
  }

  // attach convenience fields (optional)
  (req as any).rls = { userId: user.sub, organizationId: user.org };
}