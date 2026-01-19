// src/routes/webhooks.ts
import type { FastifyInstance } from "fastify";
import crypto from "node:crypto";

import { paymentConfig } from "../config/payment.config.js";
import { finalizePaystackChargeSuccess } from "../services/paystack_finalize.service.js";
import { setPgContext } from "../db/set_pg_context.js";

type WebhookCtx = {
  organizationId: string;
  actorUserId: string | null;
  reference: string;
};

function normalizeSig(sigHeaderRaw: string): string {
  return String(sigHeaderRaw ?? "")
    .trim()
    .toLowerCase()
    .replace(/^sha512=/i, "")
    .trim();
}

function safeTimingEqualHex(aHex: string, bHex: string): boolean {
  try {
    const a = Buffer.from(aHex, "hex");
    const b = Buffer.from(bHex, "hex");
    return a.length === b.length && crypto.timingSafeEqual(a, b);
  } catch {
    return false;
  }
}

function extractPaystackReference(event: any): string {
  return String(
    event?.data?.reference ??
      event?.data?.metadata?.reference ??
      event?.data?.metadata?.ref ??
      event?.reference ??
      ""
  ).trim();
}

/**
 * Fast org/actor resolution:
 * We avoid information_schema lookups on every webhook.
 *
 * Strategy:
 * 1) Try "payments.transaction_reference" (your schema already uses this in purchases routes).
 * 2) Fall back to "payments.reference" (common).
 * 3) If neither exists, skip resolve (log) and return ok:true.
 *
 * NOTE: If your payments table uses a different column, add it to TRY_REFS below.
 */
async function resolveWebhookContext(pg: any, event: any): Promise<WebhookCtx | null> {
  const reference = extractPaystackReference(event);
  if (!reference) return null;

  // Columns we will try in order (most likely first)
  const TRY_REFS = [
    "transaction_reference",
    "reference",
    "provider_reference",
    "gateway_reference",
    "paystack_reference",
    "external_reference",
  ] as const;

  // Optional actor columns (first match wins via COALESCE)
  const TRY_ACTORS = [
    "created_by_user_id",
    "created_by",
    "user_id",
    "payer_id",
    "customer_id",
    "actor_user_id",
  ] as const;

  // We cannot parameterize column names, so we must keep this strictly controlled.
  // We'll probe using "to_regclass" + "exists column" checks only once per request,
  // but WITHOUT reading information_schema repeatedly.
  //
  // Cheap check for column existence:
  // SELECT 1 FROM pg_attribute WHERE attrelid='public.payments'::regclass AND attname='...'
  async function hasColumn(col: string): Promise<boolean> {
    const { rows } = await pg.query(
      `
      select 1
      from pg_attribute
      where attrelid = 'public.payments'::regclass
        and attname = $1
        and attisdropped = false
      limit 1;
      `,
      [col]
    );
    return !!rows?.[0];
  }

  // Find first existing ref column
  let refCol: string | null = null;
  for (const c of TRY_REFS) {
    // eslint-disable-next-line no-await-in-loop
    if (await hasColumn(c)) {
      refCol = c;
      break;
    }
  }
  if (!refCol) return null;

  // Find existing actor cols (0..N)
  const actorCols: string[] = [];
  for (const c of TRY_ACTORS) {
    // eslint-disable-next-line no-await-in-loop
    if (await hasColumn(c)) actorCols.push(c);
  }

  const actorSelect =
    actorCols.length > 0
      ? `coalesce(${actorCols.map((c) => `p.${c}::text`).join(", ")})`
      : `null::text`;

  const { rows } = await pg.query(
    `
    select
      p.organization_id::text as organization_id,
      ${actorSelect} as actor_user_id
    from public.payments p
    where p.${refCol} = $1
    limit 1;
    `,
    [reference]
  );

  const row = rows?.[0];
  if (!row?.organization_id) return null;

  return {
    organizationId: String(row.organization_id).trim(),
    actorUserId: row.actor_user_id ? String(row.actor_user_id).trim() : null,
    reference,
  };
}

export async function webhooksRoutes(app: FastifyInstance) {
  app.post(
    "/webhooks/paystack",
    {
      // if fastify-raw-body is registered, this will attach request.rawBody
      config: { rawBody: true },
    },
    async (request, reply) => {
      const secret = String(paymentConfig.paystack.webhookSecret ?? "").trim();
      if (!secret) {
        return reply.code(500).send({ ok: false, error: "WEBHOOK_SECRET_MISSING" });
      }

      const sigHeaderRaw = String(request.headers["x-paystack-signature"] ?? "").trim();
      if (!sigHeaderRaw) {
        return reply.code(400).send({ ok: false, error: "SIGNATURE_MISSING" });
      }

      const signature = normalizeSig(sigHeaderRaw);
      if (!/^[0-9a-f]{128}$/.test(signature)) {
        return reply.code(400).send({ ok: false, error: "SIGNATURE_INVALID_FORMAT" });
      }

      // ---- A) Hash JSON.stringify(body) ----
      const bodyObj: any = (request as any).body ?? {};
      const bodyString = JSON.stringify(bodyObj);

      const jsonHashHex = crypto
        .createHmac("sha512", secret)
        .update(bodyString)
        .digest("hex")
        .toLowerCase();

      let ok = safeTimingEqualHex(signature, jsonHashHex);

      // ---- B) If JSON hash fails, try raw body hash (if available) ----
      let rawHashHex: string | null = null;
      const rawAny = (request as any).rawBody as Buffer | string | undefined;

      let rawBuf: Buffer | null = null;
      if (Buffer.isBuffer(rawAny)) rawBuf = rawAny;
      else if (typeof rawAny === "string") rawBuf = Buffer.from(rawAny, "utf8");

      if (!ok && rawBuf && rawBuf.length > 0) {
        rawHashHex = crypto
          .createHmac("sha512", secret)
          .update(rawBuf)
          .digest("hex")
          .toLowerCase();

        ok = safeTimingEqualHex(signature, rawHashHex);
      }

      if (!ok) {
        // SAFE DEBUG — no secret value exposed
        const debug = {
          secretLen: secret.length,
          secretPrefix: secret.slice(0, 6),
          secretSuffix: secret.slice(-4),

          signaturePrefix: signature.slice(0, 16),
          signatureSuffix: signature.slice(-16),

          jsonHashPrefix: jsonHashHex.slice(0, 16),
          jsonHashSuffix: jsonHashHex.slice(-16),

          rawHashPrefix: rawHashHex ? rawHashHex.slice(0, 16) : null,
          rawHashSuffix: rawHashHex ? rawHashHex.slice(-16) : null,

          bodyStringLen: bodyString.length,
          rawBodyType: rawAny == null ? null : Buffer.isBuffer(rawAny) ? "buffer" : typeof rawAny,
          rawLen: rawBuf ? rawBuf.length : 0,
        };

        app.log.warn(debug, "paystack signature mismatch");

        const isProd = String(process.env.NODE_ENV || "").toLowerCase() === "production";
        return reply
          .code(401)
          .send(isProd ? { ok: false, error: "INVALID_SIGNATURE" } : { ok: false, error: "INVALID_SIGNATURE", debug });
      }

      // ✅ Verified event
      const event = bodyObj;

      app.log.info(
        { event: event?.event, dataRef: event?.data?.reference },
        "paystack webhook received"
      );

      // finalize in DB (Pool-safe Option A)
      // @ts-ignore
      const pg = await app.pg.connect();
      try {
        await pg.query("BEGIN");
        await pg.query("SET LOCAL TIME ZONE 'UTC'");

        const ctx = await resolveWebhookContext(pg, event);
        if (!ctx?.organizationId) {
          app.log.warn(
            { reference: extractPaystackReference(event), eventType: event?.event },
            "webhook ctx not resolved (no org found) — skipping finalize"
          );
          await pg.query("COMMIT");
          return reply.send({ ok: true });
        }

        // Prefer explicit system actor from env, else actor from payment, else empty string
        const systemActor = String(process.env.WEBHOOK_ACTOR_USER_ID ?? "").trim();
        const actorUserId = (systemActor || ctx.actorUserId || "").trim();

        await setPgContext(pg, {
          userId: actorUserId || null,
          organizationId: ctx.organizationId,
          role: "admin",
          eventNote: `paystack:${String(event?.event ?? "event")}:${ctx.reference}`,
        });

        const res = await finalizePaystackChargeSuccess(pg, event);
        if (!res.ok) {
          app.log.warn(
            { error: res.error, message: res.message, reference: ctx.reference, orgId: ctx.organizationId },
            "paystack finalize skipped/failed"
          );
        }

        await pg.query("COMMIT");
      } catch (e) {
        try {
          await pg.query("ROLLBACK");
        } catch {}
        app.log.error(e, "paystack finalize failed");
        // still return 200 to avoid retry storms
      } finally {
        pg.release();
      }

      return reply.send({ ok: true });
    }
  );
}