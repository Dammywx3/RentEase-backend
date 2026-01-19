// src/types/fastify.d.ts
import "fastify";
import "@fastify/jwt";
import type { FastifyReply, FastifyRequest } from "fastify";
import type { AuthUser } from "../middleware/auth.js";
import type { JwtPayload } from "../plugins/jwt.js";

declare module "@fastify/jwt" {
  interface FastifyJWT {
    payload: JwtPayload;
    user: JwtPayload; // what req.jwtVerify() sets internally (library-level typing)
  }
}

declare module "fastify" {
  interface FastifyInstance {
    /**
     * Decorated by src/plugins/jwt.ts
     */
    authenticate: (req: FastifyRequest, reply: FastifyReply) => Promise<void>;
    optionalAuthenticate: (req: FastifyRequest, reply: FastifyReply) => Promise<void>;
  }

  interface FastifyRequest {
    /**
     * Normalized identity set by middleware/auth.ts (requireAuth/optionalAuth)
     * We also attach compat fields like user.id, user.sub, user.org, etc.
     */
    user?: AuthUser & {
      id?: string;
      organization_id?: string;
      sub?: string;
      org?: string;
    };

    /**
     * Effective org ID set by middleware/auth.ts
     */
    orgId?: string;

    /**
     * Common aliases to reduce "missing field" issues in routes
     */
    userId?: string;
    role?: AuthUser["role"];

    /**
     * Legacy/optional fields (only if still used elsewhere)
     */
    rls?: {
      userId?: string;
      organizationId?: string;
    };

    auth?: {
      userId?: string;
      sub?: string;
    };
  }
}

export {};