// src/plugins/security.ts
import fp from "fastify-plugin";
import helmet from "@fastify/helmet";

export const registerSecurity = fp(async (app) => {
  const isProd = process.env.NODE_ENV === "production";

  await app.register(helmet, {
    contentSecurityPolicy: isProd ? undefined : false,

    crossOriginEmbedderPolicy: isProd ? true : false,
    crossOriginOpenerPolicy: isProd ? { policy: "same-origin" } : false,
    crossOriginResourcePolicy: isProd ? { policy: "same-site" } : false,

    referrerPolicy: { policy: "no-referrer" },
    hsts: isProd
      ? { maxAge: 15552000, includeSubDomains: true, preload: true }
      : false,

    frameguard: { action: "deny" },
  });
});
