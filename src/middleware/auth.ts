// src/middleware/auth.ts
import type { FastifyReply, FastifyRequest } from "fastify";

/**
 * Normalized user object we attach to req.user
 * NOTE: keep these canonical names for internal consistency:
 * - userId
 * - organizationId
 * - role
 */
export type AuthUser = {
  userId: string;
  organizationId: string;
  role: "tenant" | "landlord" | "agent" | "admin";
  email?: string;

  /**
   * Back-compat fields that some routes expect:
   * - id (many routes expect request.user.id)
   * - organization_id (some DB-shaped code expects request.user.organization_id)
   * - sub/org (JWT-style access)
   */
  id?: string;
  organization_id?: string;
  sub?: string;
  org?: string;
};

const ALLOWED_ROLES = new Set<AuthUser["role"]>(["tenant", "landlord", "agent", "admin"]);

/**
 * Raw JWT payload can vary depending on what you sign:
 * - Some code uses { sub, org, role }
 * - Some uses { userId, organizationId, role }
 */
type RawJwtPayload = Partial<{
  userId: string;
  organizationId: string;
  role: string;
  email: string;

  // common JWT-style fields
  sub: string;
  org: string;

  iat: number;
  exp: number;
}>;

function getBearerToken(req: FastifyRequest): string | null {
  const header = req.headers.authorization;
  if (!header) return null;

  const [type, token] = header.trim().split(/\s+/);
  if (type?.toLowerCase() !== "bearer" || !token) return null;

  return token.trim();
}

function normalizeJwtPayload(raw: RawJwtPayload): AuthUser | null {
  const userId = String(raw.userId ?? raw.sub ?? "").trim();
  const organizationId = String(raw.organizationId ?? raw.org ?? "").trim();
  const roleRaw = String(raw.role ?? "").trim();

  if (!userId || !organizationId || !roleRaw) return null;
  if (!ALLOWED_ROLES.has(roleRaw as AuthUser["role"])) return null;

  return {
    userId,
    organizationId,
    role: roleRaw as AuthUser["role"],
    email: raw.email ? String(raw.email) : undefined,
  };
}

function getOrgHeader(req: FastifyRequest): string {
  return String(req.headers["x-organization-id"] ?? "").trim();
}

/**
 * Enforce org rules and attach req.orgId.
 */
function enforceOrg(
  req: FastifyRequest,
  reply: FastifyReply,
  user: AuthUser,
  opts: { requireHeader: boolean }
): boolean {
  const headerOrg = getOrgHeader(req);

  // For protected routes: header MUST exist
  if (opts.requireHeader && !headerOrg) {
    reply.code(400).send({
      ok: false,
      error: "ORG_REQUIRED",
      message: "x-organization-id required",
    });
    return false;
  }

  // If header present, it MUST match token org (spoof protection)
  if (headerOrg && headerOrg !== user.organizationId) {
    reply.code(403).send({
      ok: false,
      error: "FORBIDDEN",
      message: "Token org does not match x-organization-id",
    });
    return false;
  }

  // Effective org
  (req as any).orgId = headerOrg || user.organizationId;
  return true;
}

/**
 * ✅ Canonical + Back-compat identity attachment
 */
function attachCompatAuthFields(req: FastifyRequest, user: AuthUser) {
  const orgId = String((req as any).orgId ?? user.organizationId).trim();

  // ✅ Ensure req.user is the normalized user
  (req as any).user = user;

  // ✅ Common route expectations
  (req as any).user.id = user.userId;             // request.user.id
  (req as any).user.organization_id = orgId;      // request.user.organization_id
  (req as any).user.sub = user.userId;            // request.user.sub
  (req as any).user.org = orgId;                  // request.user.org

  // ✅ Top-level aliases (some routes expect these)
  (req as any).userId = user.userId;
  (req as any).role = user.role;

  // ✅ Legacy helpers
  (req as any).rls = { userId: user.userId, organizationId: orgId };
  (req as any).auth = { userId: user.userId, sub: user.userId };
}

/**
 * Must be logged in (valid JWT).
 * ✅ Requires x-organization-id and enforces match with token org.
 * ✅ Attaches req.user and req.orgId.
 */
export async function requireAuth(req: FastifyRequest, reply: FastifyReply) {
  try {
    const raw = (await (req as any).jwtVerify()) as RawJwtPayload;

    const user = normalizeJwtPayload(raw);
    if (!user) {
      return reply.code(401).send({
        ok: false,
        error: "UNAUTHORIZED",
        message: "Invalid token payload",
      });
    }

    // temp attach (org enforcement uses it)
    (req as any).user = user;

    if (!enforceOrg(req, reply, user, { requireHeader: true })) return;

    // ✅ After org is resolved, finalize all compat fields
    attachCompatAuthFields(req, user);
  } catch {
    return reply.code(401).send({
      ok: false,
      error: "UNAUTHORIZED",
      message: "Invalid or missing token",
    });
  }
}

/**
 * Optional auth:
 * - If token exists, verify and attach req.user + req.orgId.
 * - If header org exists, must match token org.
 * - If header missing, fall back to token org.
 */
export async function optionalAuth(req: FastifyRequest, reply: FastifyReply) {
  const token = getBearerToken(req);
  if (!token) return;

  try {
    const raw = (await (req as any).jwtVerify()) as RawJwtPayload;

    const user = normalizeJwtPayload(raw);
    if (!user) {
      return reply.code(401).send({
        ok: false,
        error: "UNAUTHORIZED",
        message: "Invalid token payload",
      });
    }

    (req as any).user = user;

    if (!enforceOrg(req, reply, user, { requireHeader: false })) return;

    attachCompatAuthFields(req, user);
  } catch {
    return reply.code(401).send({
      ok: false,
      error: "UNAUTHORIZED",
      message: "Invalid token",
    });
  }
}

/**
 * Role guard factory.
 */
export function requireRole(...roles: AuthUser["role"][]) {
  return async function roleGuard(req: FastifyRequest, reply: FastifyReply) {
    const user = (req as any).user as AuthUser | undefined;

    if (!user) {
      return reply.code(401).send({
        ok: false,
        error: "UNAUTHORIZED",
        message: "Login required",
      });
    }

    if (!roles.includes(user.role)) {
      return reply.code(403).send({
        ok: false,
        error: "FORBIDDEN",
        message: "You do not have permission to access this resource",
      });
    }
  };
}

export const requireAdmin = [requireAuth, requireRole("admin")];