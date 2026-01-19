// src/plugins/jwt.ts
import fp from "fastify-plugin";
import fastifyJwt from "@fastify/jwt";
import type { FastifyReply, FastifyRequest } from "fastify";

import { env } from "../config/env.js";
import { requireAuth, optionalAuth } from "../middleware/auth.js";

export type JwtPayload = {
  sub: string;
  org: string;
  role: "tenant" | "landlord" | "agent" | "admin";
  email?: string;
};

export default fp(async (app) => {
  await app.register(fastifyJwt, { secret: env.jwtSecret });

  /**
   * ✅ Strict auth guard (recommended for all protected routes)
   * - JWT required
   * - x-organization-id REQUIRED
   * - header org MUST match token org
   * - sets req.user + req.orgId
   */
  app.decorate("authenticate", async (req: FastifyRequest, reply: FastifyReply) => {
    return requireAuth(req, reply);
  });

  /**
   * ✅ Optional auth (use only when route should work logged-out too)
   * - JWT optional
   * - if header org exists, must match token org
   * - sets req.user + req.orgId when token is present
   */
  app.decorate("optionalAuthenticate", async (req: FastifyRequest, reply: FastifyReply) => {
    return optionalAuth(req, reply);
  });
});