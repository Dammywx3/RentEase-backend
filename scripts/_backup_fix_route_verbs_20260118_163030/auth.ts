// src/routes/auth.ts
import type { FastifyInstance } from "fastify";
import { registerSchema, loginSchema } from "../schemas/auth.schema.js";
import { hashPassword, verifyPassword } from "../shared/utils/password.js";
import {
  createUser,
  getUserByEmail,
  markLoginFailure,
  markLoginSuccess,
} from "../repositories/users.repo.js";

export async function authRoutes(app: FastifyInstance) {
  // Register
  app.post("/register", async (req, reply) => {
    const body = registerSchema.parse(req.body);

    const passwordHash = await hashPassword(body.password);

    try {
      const user = await createUser({
        organizationId: body.organizationId,
        fullName: body.fullName,
        email: body.email.toLowerCase(),
        phone: body.phone,
        passwordHash,
        role: body.role,
      });

      const token = app.jwt.sign({
        sub: user.id,
        org: String(user.organization_id ?? ""),
        role: user.role,
        email: user.email,
      });

      return reply.code(201).send({
        ok: true,
        token,
        user,
      });
    } catch (err: any) {
      // unique violation in Postgres
      if (err?.code === "23505") {
        return reply.code(409).send({
          ok: false,
          error: "EMAIL_EXISTS",
          message: "Email already registered",
        });
      }
      throw err;
    }
  });

  // Login
  app.post("/login", async (req, reply) => {
    const body = loginSchema.parse(req.body);

    const user = await getUserByEmail(body.email.toLowerCase());
    if (!user) {
      return reply
        .code(401)
        .send({ ok: false, error: "UNAUTHORIZED", message: "Invalid credentials" });
    }

    // ✅ 0) permanent lock check
    if (user.account_locked_permanent) {
      return reply.code(423).send({
        ok: false,
        error: "ACCOUNT_LOCKED",
        message: "Account locked. Contact support.",
      });
    }

    // ✅ 1) temp lock check
    if (user.account_locked_until) {
      const lockedUntil = new Date(user.account_locked_until);
      if (lockedUntil.getTime() > Date.now()) {
        return reply.code(423).send({
          ok: false,
          error: "ACCOUNT_LOCKED",
          message: "Too many attempts. Try again in 5 minutes.",
          lockedUntil,
        });
      }
      // if expired, allow login attempt (repo handles stage escalation on next wrong)
    }

    const ok = await verifyPassword(body.password, user.password_hash);

    if (!ok) {
      const { attempts, lockedUntil, permanentlyLocked } = await markLoginFailure(
        user.id
      );

      // ✅ permanent lock just triggered
      if (permanentlyLocked) {
        return reply.code(423).send({
          ok: false,
          error: "ACCOUNT_LOCKED",
          message: "Account locked. Contact support.",
        });
      }

      // ✅ temp lock just triggered (3rd wrong)
      if (lockedUntil) {
        return reply.code(423).send({
          ok: false,
          error: "ACCOUNT_LOCKED",
          message: "Too many attempts. Try again in 5 minutes.",
          attempts,
          lockedUntil,
        });
      }

      // normal wrong attempt (1st/2nd)
      return reply.code(401).send({
        ok: false,
        error: "UNAUTHORIZED",
        message: "Invalid credentials",
        attempts,
      });
    }

    // ✅ success resets attempts + locks + stage
    await markLoginSuccess(user.id);

    const token = app.jwt.sign({
      sub: user.id,
      org: String(user.organization_id ?? ""),
      role: user.role,
      email: user.email,
    });

    return reply.send({
      ok: true,
      token,
      user: {
        id: user.id,
        organization_id: user.organization_id,
        full_name: user.full_name,
        email: user.email,
        phone: user.phone,
        role: user.role,
        verified_status: user.verified_status,
      },
    });
  });
}