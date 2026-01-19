// src/plugins/raw_body.js
import fp from "fastify-plugin";
import rawBody from "fastify-raw-body";


export const rawBodyPlugin = fp(async function rawBodyPlugin(fastify) {
  await fastify.register(rawBody, {
    field: "rawBody",
    global: false,
    encoding: false,
    runFirst: true,
  });
});
