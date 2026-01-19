import fp from "fastify-plugin";
import cors from "@fastify/cors";
import type { FastifyCorsOptions } from "@fastify/cors";

export const registerCors = fp<FastifyCorsOptions>(async (app) => {
  await app.register(cors, {
    origin: true,
    credentials: true,
  });
});
