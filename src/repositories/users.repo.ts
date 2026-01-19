// src/repositories/users.repo.ts
import type { PoolClient } from "pg";
import { withTransaction } from "../config/database.js";

export type DbUser = {
  id: string;
  organization_id: string | null;
  full_name: string;
  email: string;
  phone: string | null;
  password_hash: string;
  role: "tenant" | "landlord" | "agent" | "admin";
  verified_status: string | null;

  last_login: string | null;

  failed_login_attempts: number | null;
  account_locked_until: string | null;

  // ✅ new columns you added
  account_locked_permanent?: boolean | null;
  lock_stage?: number | null;

  created_at: string;
  updated_at: string;
};

export async function getUserByEmail(email: string): Promise<DbUser | null> {
  return withTransaction(async (client: PoolClient) => {
    const { rows } = await client.query<DbUser>(
      `
      SELECT
        id,
        organization_id,
        full_name,
        email,
        phone,
        password_hash,
        role,
        verified_status,
        last_login,
        failed_login_attempts,
        account_locked_until,
        account_locked_permanent,
        lock_stage,
        created_at,
        updated_at
      FROM public.users
      WHERE email = $1
      LIMIT 1
      `,
      [email]
    );

    return rows[0] ?? null;
  });
}

export async function createUser(input: {
  organizationId: string;
  fullName: string;
  email: string;
  phone?: string;
  passwordHash: string;
  role: DbUser["role"];
}): Promise<
  Pick<
    DbUser,
    "id" | "organization_id" | "full_name" | "email" | "phone" | "role" | "verified_status" | "created_at"
  >
> {
  return withTransaction(async (client: PoolClient) => {
    const { rows } = await client.query(
      `
      INSERT INTO public.users (
        organization_id, full_name, email, phone, password_hash, role
      )
      VALUES ($1, $2, $3, $4, $5, $6)
      RETURNING id, organization_id, full_name, email, phone, role, verified_status, created_at
      `,
      [input.organizationId, input.fullName, input.email, input.phone ?? null, input.passwordHash, input.role]
    );

    return rows[0];
  });
}

/**
 * ✅ On successful login:
 * - reset attempts
 * - clear temp lock
 * - clear permanent lock
 * - reset lock_stage
 */
export async function markLoginSuccess(userId: string): Promise<void> {
  await withTransaction(async (client: PoolClient) => {
    await client.query(
      `
      UPDATE public.users
      SET last_login = now(),
          failed_login_attempts = 0,
          account_locked_until = NULL,
          account_locked_permanent = false,
          lock_stage = 0,
          updated_at = now()
      WHERE id = $1
      `,
      [userId]
    );
  });
}

/**
 * ✅ Your policy:
 * 1) wrong 3x => temp lock 5 minutes and lock_stage=1
 * 2) after temp lock expires, next wrong => permanent lock (account_locked_permanent=true)
 *
 * Returns:
 * - attempts
 * - lockedUntil (if temp lock applied)
 * - permanentlyLocked
 */
export async function markLoginFailure(userId: string): Promise<{
  attempts: number;
  lockedUntil: Date | null;
  permanentlyLocked: boolean;
}> {
  return withTransaction(async (client: PoolClient) => {
    // Read current state first (so we can implement stage logic)
    const { rows: curRows } = await client.query<{
      failed_login_attempts: number | null;
      account_locked_until: Date | null;
      account_locked_permanent: boolean | null;
      lock_stage: number | null;
    }>(
      `
      SELECT
        failed_login_attempts,
        account_locked_until,
        account_locked_permanent,
        lock_stage
      FROM public.users
      WHERE id = $1
      LIMIT 1
      `,
      [userId]
    );

    const cur = curRows[0];
    const now = new Date();

    // If already permanently locked, keep it locked
    if (cur?.account_locked_permanent) {
      return {
        attempts: cur.failed_login_attempts ?? 0,
        lockedUntil: null,
        permanentlyLocked: true,
      };
    }

    const lockStage = cur?.lock_stage ?? 0;
    const lockedUntil = cur?.account_locked_until ?? null;

    const lockExpired = !lockedUntil || lockedUntil.getTime() <= now.getTime();

    // If they've already used temp lock (stage 1) AND lock is expired,
    // then the NEXT wrong attempt becomes permanent lock.
    if (lockStage >= 1 && lockExpired) {
      await client.query(
        `
        UPDATE public.users
        SET account_locked_permanent = true,
            account_locked_until = NULL,
            updated_at = now()
        WHERE id = $1
        `,
        [userId]
      );

      return {
        attempts: cur?.failed_login_attempts ?? 0,
        lockedUntil: null,
        permanentlyLocked: true,
      };
    }

    // Otherwise increment attempts
    const { rows: incRows } = await client.query<{ failed_login_attempts: number }>(
      `
      UPDATE public.users
      SET failed_login_attempts = COALESCE(failed_login_attempts, 0) + 1,
          updated_at = now()
      WHERE id = $1
      RETURNING failed_login_attempts
      `,
      [userId]
    );

    const attempts = incRows[0]?.failed_login_attempts ?? 1;

    // On 3rd wrong attempt => temp lock 5 minutes (stage 1)
    if (attempts >= 3) {
      const { rows: lockRows } = await client.query<{ account_locked_until: Date }>(
        `
        UPDATE public.users
        SET account_locked_until = now() + interval '5 minutes',
            lock_stage = 1,
            updated_at = now()
        WHERE id = $1
        RETURNING account_locked_until
        `,
        [userId]
      );

      return {
        attempts,
        lockedUntil: lockRows[0]?.account_locked_until ?? null,
        permanentlyLocked: false,
      };
    }

    // Not locked yet
    return {
      attempts,
      lockedUntil: null,
      permanentlyLocked: false,
    };
  });
}