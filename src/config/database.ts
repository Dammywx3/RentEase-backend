// src/config/database.ts
import { Pool, type PoolClient } from "pg";
import type { QueryResult, QueryResultRow } from "pg";
import { env } from "./env.js";
import { setPgContext } from "../db/set_pg_context.js";

export const pool = new Pool({
  connectionString: env.databaseUrl,
  max: Number(process.env.DB_POOL_MAX ?? 10),
  idleTimeoutMillis: Number(process.env.DB_IDLE_TIMEOUT_MS ?? 30_000),
  statement_timeout: Number(process.env.DB_STATEMENT_TIMEOUT_MS ?? 15_000),
});

export function query<T extends QueryResultRow = any>(
  text: string,
  params: readonly any[] = []
): Promise<QueryResult<T>> {
  return pool.query<T>(text, params as any);
}

export async function withTransaction<T>(fn: (client: PoolClient) => Promise<T>): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SET LOCAL TIME ZONE 'UTC'");

    const result = await fn(client);

    await client.query("COMMIT");
    return result;
  } catch (err) {
    try {
      await client.query("ROLLBACK");
    } catch {}
    throw err;
  } finally {
    client.release();
  }
}

export type RlsContext = {
  userId: string;
  organizationId: string;
  role?: string | null;
  eventNote?: string | null;
};

export async function withRlsTransaction<T>(
  ctx: RlsContext,
  fn: (client: PoolClient) => Promise<T>
): Promise<T> {
  if (!ctx.userId) throw new Error("withRlsTransaction missing userId");
  if (!ctx.organizationId) throw new Error("withRlsTransaction missing organizationId");

  return withTransaction(async (client) => {
    // ✅ MUST be after BEGIN because set_config(..., true) is LOCAL
    await setPgContext(client, {
      userId: ctx.userId,
      organizationId: ctx.organizationId,
      role: ctx.role ?? null,
      eventNote: ctx.eventNote ?? null,
    });

    return fn(client);
  });
}

export async function closePool(): Promise<void> {
  await pool.end();
}