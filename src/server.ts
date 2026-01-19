// src/server.ts
import "dotenv/config";
import Fastify from "fastify";
import postgres from "@fastify/postgres";

import { rawBodyPlugin } from "./plugins/raw_body.js";
import { env } from "./config/env.js";
import { prisma } from "./lib/prisma.js";

import { registerCors } from "./plugins/cors.js";
import registerJwt from "./plugins/jwt.js";
import { registerSecurity } from "./plugins/security.js";

import { registerErrorHandler } from "./middleware/error.middleware.js";
import { registerRateLimit } from "./middleware/rateLimit.middleware.js";

import { registerRoutes } from "./routes/index.js";
import { closePool } from "./config/database.js";

async function start() {
  const app = Fastify({ logger: true });

  // 1) Error handler early
  registerErrorHandler(app);

  // 2) Core plugins
  await app.register(registerCors);
  await app.register(registerSecurity);
  await app.register(registerJwt);

  // ✅ Raw body capture for webhook signature verification
  // IMPORTANT: register plugin via app.register (not calling function directly)
  await app.register(rawBodyPlugin);

  // ✅ fastify-postgres (app.pg.connect() support)
  const connectionString =
    process.env.DATABASE_URL ||
    (env as any).databaseUrl ||
    (env as any).dbUrl ||
    (env as any).database_url ||
    `postgres://localhost:5432/${process.env.DB_NAME || "rentease"}`;

  await app.register(postgres, { connectionString });

  // 3) Global rate limit
  await app.register(registerRateLimit, {
    global: { max: 200, timeWindow: "1 minute" },
  });

  // 4) Routes
  await app.register(registerRoutes);

  // Debug routes
  app.get("/debug/routes", async () => {
    // @ts-ignore
    return app.printRoutes();
  });

  // DB ping (temporary)
  app.get("/v1/db/ping", async () => {
    await prisma.$queryRaw`SELECT 1`;
    return { ok: true, db: "connected" };
  });

  // Graceful shutdown
  app.addHook("onClose", async () => {
    await prisma.$disconnect();
    await closePool();
  });

  // ✅ IMPORTANT for production hosting (Render/AWS/etc):
  // - Platforms inject PORT
  // - Host should be 0.0.0.0 (or HOST env)
  const port = Number(process.env.PORT ?? env.port ?? 4000);
  const host = process.env.HOST ?? "0.0.0.0";

  await app.listen({ port, host });
  app.log.info(`Server listening at http://${host}:${port}`);
}

start().catch((err) => {
  console.error(err);
  process.exit(1);
});