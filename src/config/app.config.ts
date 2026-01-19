import "dotenv/config";

function must(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing env var: ${name}`);
  return v;
}

export const config = {
  env: process.env.NODE_ENV ?? "development",
  port: Number(process.env.PORT ?? 4000),

  jwt: {
    secret: must("JWT_SECRET"),
    expiresIn: process.env.JWT_EXPIRES_IN ?? "7d",
  },

  db: {
    url: must("DATABASE_URL"),
    max: Number(process.env.DB_POOL_MAX ?? 10),
    idleTimeoutMillis: Number(process.env.DB_IDLE_TIMEOUT_MS ?? 30000),
    statementTimeout: Number(process.env.DB_STATEMENT_TIMEOUT_MS ?? 15000),
  },
} as const;