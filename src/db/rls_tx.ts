// src/db/rls_tx.ts
import type { PoolClient } from "pg";
import { withTransaction } from "../config/database.js";
import { setPgContext, type PgContextOpts } from "./set_pg_context.js";

export type RlsContext = {
  userId: string;
  organizationId: string;
  role?: string | null;
  eventNote?: string | null;
};

function mustId(name: string, v: unknown): string {
  const s = String(v ?? "").trim();
  if (!s) throw new Error(`withRlsTransaction missing ${name}`);
  return s;
}

/**
 * ✅ Option A (Recommended for Pool):
 * - BEGIN (per-connection)
 * - SET LOCAL settings (LOCAL=true in set_config)
 * - run queries
 * - COMMIT/ROLLBACK
 *
 * Why: prevents RLS context leaking to the next request on the same pooled connection.
 */
export async function withRlsTransaction<T>(
  ctx: RlsContext,
  fn: (client: PoolClient) => Promise<T>
): Promise<T> {
  const userId = mustId("userId", ctx?.userId);
  const organizationId = mustId("organizationId", ctx?.organizationId);

  return withTransaction(async (client) => {
    // ✅ Force UTC for this transaction
    await client.query("SET LOCAL TIME ZONE 'UTC'");

    const opts: PgContextOpts = {
      userId,
      organizationId,
      role: ctx.role ?? null,
      eventNote: ctx.eventNote ?? null,
    };

    // ✅ sets BOTH: app.current_user/app.user_id AND app.organization_id/app.current_organization
    // ✅ uses LOCAL=true (scoped to current TX)
    await setPgContext(client, opts);

    return fn(client);
  });
}