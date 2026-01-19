import fp from "fastify-plugin";
import rateLimit from "@fastify/rate-limit";

export const registerRateLimit = fp(async (app) => {
  await app.register(rateLimit, {
    global: false, // we'll enable globally in server.ts with options
  });
});
