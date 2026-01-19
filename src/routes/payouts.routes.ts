import type { FastifyInstance } from "fastify";
import { setPgContext } from "../db/set_pg_context.js";
import { assertRlsContextWithUser } from "../db/rls_guard.js";
import { createPaystackPayoutAccount, requestPayout, processPayoutPaystack } from "../services/payouts.service.js";

function getOrgIdFromReq(request: any): string {
  return String(request.orgId || "").trim();
}
function getActorId(request: any): string {
  return String(
    request.user?.id ||
      request.user?.userId ||
      request.userId ||
      request.sub ||
      request.user?.sub ||
      ""
  ).trim();
}
function getRole(request: any): string | null {
  const role = String(request?.user?.role || request?.role || "").trim();
  return role || null;
}
function requireOrgId(request: any, reply: any): string | null {
  const orgId = getOrgIdFromReq(request);
  if (!orgId) {
    reply.code(400).send({ ok: false, error: "ORG_REQUIRED" });
    return null;
  }
  return orgId;
}
function requireActorId(request: any, reply: any): string | null {
  const actorId = getActorId(request);
  if (!actorId) {
    reply.code(401).send({ ok: false, error: "UNAUTHORIZED" });
    return null;
  }
  return actorId;
}

export async function payoutRoutes(fastify: FastifyInstance) {
  // ---------------------------
  // Payout Accounts
  // ---------------------------
  fastify.get("/payout-accounts", { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const orgId = requireOrgId(request, reply); if (!orgId) return;
    const actorId = requireActorId(request, reply); if (!actorId) return;
    const role = getRole(request);

    const client = await fastify.pg.connect();
    try {
      await client.query("BEGIN");
      await client.query("SET LOCAL TIME ZONE 'UTC'");
      await setPgContext(client, { organizationId: orgId, userId: actorId, role });
      await assertRlsContextWithUser(client);

      const { rows } = await client.query(
        `
        select
          id::text, provider, provider_token, currency,
          label, account_name, bank_name, last4,
          is_default, created_at, updated_at
        from public.payout_accounts
        where organization_id = $1::uuid
          and user_id = $2::uuid
          and deleted_at is null
        order by is_default desc, created_at desc;
        `,
        [orgId, actorId]
      );

      await client.query("COMMIT");
      return reply.send({ ok: true, data: rows });
    } catch (e: any) {
      try { await client.query("ROLLBACK"); } catch {}
      return reply.code(400).send({ ok: false, error: "LIST_PAYOUT_ACCOUNTS_FAILED", message: e?.message || String(e) });
    } finally {
      client.release();
    }
  });

  fastify.post("/payout-accounts", {
    preHandler: [fastify.authenticate],
    schema: {
      body: {
        type: "object",
        required: ["provider", "currency", "name", "accountNumber", "bankCode"],
        additionalProperties: false,
        properties: {
          provider: { type: "string", enum: ["paystack"] },
          currency: { type: "string", minLength: 3, maxLength: 3 },
          label: { type: "string" },
          name: { type: "string", minLength: 2 },
          accountNumber: { type: "string", minLength: 6 },
          bankCode: { type: "string", minLength: 2 },
          bankName: { type: "string" },
          makeDefault: { type: "boolean" },
        },
      },
    },
  }, async (request: any, reply: any) => {
    const orgId = requireOrgId(request, reply); if (!orgId) return;
    const actorId = requireActorId(request, reply); if (!actorId) return;
    const role = getRole(request);

    const body = request.body || {};

    const client = await fastify.pg.connect();
    try {
      await client.query("BEGIN");
      await client.query("SET LOCAL TIME ZONE 'UTC'");
      await setPgContext(client, { organizationId: orgId, userId: actorId, role });
      await assertRlsContextWithUser(client);

      if (String(body.provider) !== "paystack") {
        await client.query("ROLLBACK");
        return reply.code(400).send({ ok: false, error: "UNSUPPORTED_PROVIDER" });
      }

      const res = await createPaystackPayoutAccount(client, {
        organizationId: orgId,
        userId: actorId,
        currency: String(body.currency || "NGN"),
        label: body.label ?? null,
        name: String(body.name),
        accountNumber: String(body.accountNumber),
        bankCode: String(body.bankCode),
        bankName: body.bankName ?? null,
        makeDefault: Boolean(body.makeDefault ?? false),
      });

      await client.query("COMMIT");
      return reply.send({ ok: true, data: res });
    } catch (e: any) {
      try { await client.query("ROLLBACK"); } catch {}
      return reply.code(400).send({ ok: false, error: "CREATE_PAYOUT_ACCOUNT_FAILED", message: e?.message || String(e) });
    } finally {
      client.release();
    }
  });

  // ---------------------------
  // Payouts
  // ---------------------------
  fastify.get("/", { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const orgId = requireOrgId(request, reply); if (!orgId) return;
    const actorId = requireActorId(request, reply); if (!actorId) return;
    const role = getRole(request);

    const client = await fastify.pg.connect();
    try {
      await client.query("BEGIN");
      await client.query("SET LOCAL TIME ZONE 'UTC'");
      await setPgContext(client, { organizationId: orgId, userId: actorId, role });
      await assertRlsContextWithUser(client);

      const { rows } = await client.query(
        `
        select
          p.id::text,
          p.amount, p.currency, p.status::text,
          p.gateway_payout_id,
          p.requested_at, p.processed_at,
          p.created_at, p.updated_at,
          pa.provider, pa.bank_name, pa.last4, pa.account_name, pa.label
        from public.payouts p
        join public.payout_accounts pa on pa.id = p.payout_account_id
        where p.organization_id = $1::uuid
          and p.user_id = $2::uuid
        order by p.requested_at desc
        limit 50;
        `,
        [orgId, actorId]
      );

      await client.query("COMMIT");
      return reply.send({ ok: true, data: rows });
    } catch (e: any) {
      try { await client.query("ROLLBACK"); } catch {}
      return reply.code(400).send({ ok: false, error: "LIST_PAYOUTS_FAILED", message: e?.message || String(e) });
    } finally {
      client.release();
    }
  });

  fastify.post("/request", {
    preHandler: [fastify.authenticate],
    schema: {
      body: {
        type: "object",
        required: ["walletAccountId", "payoutAccountId", "amount", "currency"],
        additionalProperties: false,
        properties: {
          walletAccountId: { type: "string", format: "uuid" },
          payoutAccountId: { type: "string", format: "uuid" },
          amount: { type: "number", minimum: 0.01 },
          currency: { type: "string", minLength: 3, maxLength: 3 },
          note: { type: "string" },
        },
      },
    },
  }, async (request: any, reply: any) => {
    const orgId = requireOrgId(request, reply); if (!orgId) return;
    const actorId = requireActorId(request, reply); if (!actorId) return;
    const role = getRole(request);

    const b = request.body || {};

    const client = await fastify.pg.connect();
    try {
      await client.query("BEGIN");
      await client.query("SET LOCAL TIME ZONE 'UTC'");
      await setPgContext(client, { organizationId: orgId, userId: actorId, role, eventNote: b.note ?? null });
      await assertRlsContextWithUser(client);

      const res = await requestPayout(client, {
        organizationId: orgId,
        userId: actorId,
        walletAccountId: String(b.walletAccountId),
        payoutAccountId: String(b.payoutAccountId),
        amount: Number(b.amount),
        currency: String(b.currency),
        note: b.note ?? null,
      });

      await client.query("COMMIT");
      return reply.send({ ok: true, data: res });
    } catch (e: any) {
      try { await client.query("ROLLBACK"); } catch {}
      return reply.code(400).send({ ok: false, error: "REQUEST_PAYOUT_FAILED", message: e?.message || String(e) });
    } finally {
      client.release();
    }
  });

  // Admin/service endpoint to process payout (initiate transfer)
  fastify.post<{ Params: { payoutId: string } }>(
    "/:payoutId/process",
    { preHandler: [fastify.authenticate] },
    async (request: any, reply: any) => {
      const orgId = requireOrgId(request, reply); if (!orgId) return;
      const actorId = requireActorId(request, reply); if (!actorId) return;
      const role = getRole(request);

      // if you have a role check helper, use it. minimal guard here:
      if (role !== "admin") {
        return reply.code(403).send({ ok: false, error: "FORBIDDEN", message: "Admin only" });
      }

      const payoutId = String(request.params?.payoutId || "").trim();
      if (!payoutId) return reply.code(400).send({ ok: false, error: "PAYOUT_ID_REQUIRED" });

      const client = await fastify.pg.connect();
      try {
        await client.query("BEGIN");
        await client.query("SET LOCAL TIME ZONE 'UTC'");

        // process under admin context
        await processPayoutPaystack(client, {
          organizationId: orgId,
          payoutId,
          actorUserId: actorId,
        });

        await client.query("COMMIT");
        return reply.send({ ok: true });
      } catch (e: any) {
        try { await client.query("ROLLBACK"); } catch {}
        return reply.code(400).send({ ok: false, error: "PROCESS_PAYOUT_FAILED", message: e?.message || String(e) });
      } finally {
        client.release();
      }
    }
  );
}
