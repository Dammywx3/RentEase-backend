import { Pool } from "pg";

/**
 * Shared PG Pool
 * - Uses DATABASE_URL if present (Render/production friendly)
 * - Otherwise uses standard PG* env vars (PGHOST, PGUSER, etc.)
 */
export const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  host: process.env.PGHOST,
  port: process.env.PGPORT ? Number(process.env.PGPORT) : undefined,
  user: process.env.PGUSER,
  password: process.env.PGPASSWORD,
  database: process.env.PGDATABASE || process.env.DB_NAME,
  max: process.env.PGPOOL_MAX ? Number(process.env.PGPOOL_MAX) : 10,
  idleTimeoutMillis: process.env.PGPOOL_IDLE_MS ? Number(process.env.PGPOOL_IDLE_MS) : 30_000,
});
