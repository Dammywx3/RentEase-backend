import { Pool, type PoolClient } from "pg";
import { env } from "./env.js";

export const pool = new Pool({
  connectionString: env.databaseUrl,
  max: 10,
  idleTimeoutMillis: 30_000,
  statement_timeout: 15_000,
});

export async function withTransaction<T>(
  fn: (client: PoolClient) => Promise<T>
): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const result = await fn(client);
    await client.query("COMMIT");
    return result;
  } catch (e) {
    await client.query("ROLLBACK");
    throw e;
  } finally {
    client.release();
  }
}

export async function withRlsTransaction<T>(
  ctx: { userId: string; organizationId: string },
  fn: (client: PoolClient) => Promise<T>
): Promise<T> {
  return withTransaction(async (client) => {
    await client.query("SELECT set_config('app.current_user', $1, true)", [
      String(ctx.userId),
    ]);
    await client.query("SELECT set_config('app.current_organization', $1, true)", [
      String(ctx.organizationId),
    ]);
    return fn(client);
  });
}

export async function closePool() {
  await pool.end();
}