// src/routes/purchases.routes.ts
import type { FastifyInstance } from "fastify";
import { setPgContext } from "../db/set_pg_context.js";
import { assertRlsContextWithUser } from "../db/rls_guard.js";
import { payPropertyPurchase } from "../services/purchase_payments.service.js";
import { refundPropertyPurchase } from "../services/purchase_refunds.service.js";
import { computePlatformFeeSplit } from "../config/fees.config.js";

type PurchaseRow = {
  id: string;
  organization_id: string;
  property_id: string;
  listing_id: string | null;
  buyer_id: string;
  seller_id: string;
  agreed_price: string;
  currency: string;

  status: string;
  payment_status: string;

  deposit_amount: number | null;
  earnest_deposit_amount?: number | null;

  escrow_wallet_account_id?: string | null;
  escrow_held_amount?: number | null;
  escrow_released_amount?: number | null;
  escrow_released_at?: string | null;

  paid_at?: string | null;
  refunded_at?: string | null;

  created_at: string;
  updated_at: string;
};

function getOrgIdFromReq(request: any): string {
  // ✅ ONLY trust orgId set by fastify.authenticate middleware
  return String(request.orgId || "").trim();
}

function getActorId(request: any): string {
  // ✅ prefer user.id (matches your login response); fallback to other shapes
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
    reply.code(400).send({ ok: false, error: "ORG_REQUIRED", message: "Organization not resolved" });
    return null;
  }
  return orgId;
}

function requireActorId(request: any, reply: any): string | null {
  const actorId = getActorId(request);
  if (!actorId) {
    reply.code(401).send({ ok: false, error: "UNAUTHORIZED", message: "Missing authenticated user" });
    return null;
  }
  return actorId;
}

async function fetchPurchaseOr404(client: any, purchaseId: string, orgId: string) {
  const { rows } = await client.query(
    `
    select
      pp.id::text,
      pp.organization_id::text,
      pp.property_id::text,
      pp.listing_id::text as listing_id,
      pp.buyer_id::text,
      pp.seller_id::text,
      pp.agreed_price::text as agreed_price,
      pp.currency,
      pp.status::text as status,
      pp.payment_status::text as payment_status,

      pp.deposit_amount::numeric as deposit_amount,
      pp.earnest_deposit_amount::numeric as earnest_deposit_amount,

      pp.escrow_wallet_account_id::text as escrow_wallet_account_id,
      pp.escrow_held_amount::numeric as escrow_held_amount,
      pp.escrow_released_amount::numeric as escrow_released_amount,
      pp.escrow_released_at::text as escrow_released_at,

      pp.paid_at::text as paid_at,
      pp.refunded_at::text as refunded_at,
      pp.created_at::text as created_at,
      pp.updated_at::text as updated_at
    from public.property_purchases pp
    where pp.id = $1::uuid
      and pp.organization_id = $2::uuid
      and pp.deleted_at is null
    limit 1;
    `,
    [purchaseId, orgId]
  );

  const purchase = rows[0] as PurchaseRow | undefined;
  return purchase ?? null;
}

function escrowInvariantError(reply: any, error: string, message: string) {
  return reply.code(400).send({ ok: false, error, message });
}

export async function purchasesRoutes(fastify: FastifyInstance) {
  // ------------------------------------------------------------
  // GET /purchases (list) ✅ protected + RLS-safe
  // ------------------------------------------------------------
  fastify.get("/", { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const orgId = requireOrgId(request, reply);
    if (!orgId) return;

    const actorId = requireActorId(request, reply);
    if (!actorId) return;

    const role = getRole(request);

    const client = await fastify.pg.connect();
    try {
      await client.query("BEGIN");
      await client.query("SET LOCAL TIME ZONE 'UTC'");
      await setPgContext(client, {
        organizationId: orgId,
        userId: actorId,
        role,
      });

      
      await assertRlsContextWithUser(client);
const { rows } = await client.query(
        `
        select
          pp.id::text as id,
          pp.organization_id::text as organization_id,
          pp.property_id::text as property_id,
          pp.listing_id::text as listing_id,
          pp.buyer_id::text as buyer_id,
          pp.seller_id::text as seller_id,
          pp.agreed_price::text as agreed_price,
          pp.currency,
          pp.status::text as status,
          pp.payment_status::text as payment_status,
          pp.paid_at::text as paid_at,
          pp.paid_amount::text as paid_amount,
          pp.refunded_at::text as refunded_at,
          pp.refunded_amount::text as refunded_amount,

          pp.deposit_amount::text as deposit_amount,

          pp.escrow_wallet_account_id::text as escrow_wallet_account_id,
          pp.escrow_held_amount::text as escrow_held_amount,
          pp.escrow_released_amount::text as escrow_released_amount,
          pp.escrow_released_at::text as escrow_released_at,

          pp.created_at::text as created_at,
          pp.updated_at::text as updated_at,

          exists (
            select 1 from public.property_purchase_payments ppp
            where ppp.purchase_id = pp.id
          ) as has_payment_link,

          (
            select count(*)
            from public.wallet_transactions wt
            where wt.reference_type='purchase'
              and wt.reference_id=pp.id
          ) as ledger_txn_count

        from public.property_purchases pp
        where pp.organization_id = $1::uuid
          and pp.deleted_at is null
        order by pp.created_at desc
        limit 50;
        `,
        [orgId]
      );

      await client.query("COMMIT");
      return reply.send({ ok: true, data: rows });
    } catch (e: any) {
      try { await client.query("ROLLBACK"); } catch {}
      request.log.error(e);
      return reply.code(400).send({ ok: false, error: "LIST_FAILED", message: e?.message || String(e) });
    } finally {
      client.release();
    }
  });

  // ------------------------------------------------------------
  // GET /purchases/:purchaseId (detail) ✅ protected + RLS-safe
  // ------------------------------------------------------------
  fastify.get<{ Params: { purchaseId: string } }>(
    "/:purchaseId",
    { preHandler: [fastify.authenticate] },
    async (request, reply) => {
      const orgId = requireOrgId(request, reply);
      if (!orgId) return;

      const actorId = requireActorId(request, reply);
      if (!actorId) return;

      const role = getRole(request);
      const { purchaseId } = request.params;

      const client = await fastify.pg.connect();
      try {
        await client.query("BEGIN");
        await client.query("SET LOCAL TIME ZONE 'UTC'");
        await setPgContext(client, {
          organizationId: orgId,
          userId: actorId,
          role,
        });

        
      await assertRlsContextWithUser(client);
const { rows } = await client.query(
          `
          select
            pp.*,
            pp.id::text as id,
            pp.organization_id::text as organization_id,
            pp.property_id::text as property_id,
            pp.listing_id::text as listing_id,
            pp.buyer_id::text as buyer_id,
            pp.seller_id::text as seller_id,

            pp.status::text as status_text,
            pp.payment_status::text as payment_status_text,

            pp.escrow_wallet_account_id::text as escrow_wallet_account_id,

            coalesce((
              select jsonb_agg(jsonb_build_object(
                'payment_id', p.id::text,
                'amount', p.amount,
                'currency', p.currency,
                'status', p.status::text,
                'transaction_reference', p.transaction_reference,
                'created_at', p.created_at
              ) order by p.created_at desc)
              from public.property_purchase_payments link
              join public.payments p on p.id = link.payment_id
              where link.purchase_id = pp.id
            ), '[]'::jsonb) as payments,

            coalesce((
              select jsonb_agg(jsonb_build_object(
                'txn_type', wt.txn_type::text,
                'amount', wt.amount,
                'currency', wt.currency,
                'note', wt.note,
                'created_at', wt.created_at
              ) order by wt.created_at asc)
              from public.wallet_transactions wt
              where wt.reference_type='purchase'
                and wt.reference_id=pp.id
            ), '[]'::jsonb) as ledger

          from public.property_purchases pp
          where pp.id = $1::uuid
            and pp.organization_id = $2::uuid
            and pp.deleted_at is null
          limit 1;
          `,
          [purchaseId, orgId]
        );

        const row = rows[0];
        if (!row) {
          await client.query("ROLLBACK");
          return reply.code(404).send({ ok: false, error: "NOT_FOUND", message: "Purchase not found" });
        }

        await client.query("COMMIT");
        return reply.send({ ok: true, data: row });
      } catch (e: any) {
        try { await client.query("ROLLBACK"); } catch {}
        request.log.error(e);
        return reply.code(400).send({ ok: false, error: "DETAIL_FAILED", message: e?.message || String(e) });
      } finally {
        client.release();
      }
    }
  );

  // ------------------------------------------------------------
  // GET /purchases/:purchaseId/events ✅ protected + RLS-safe
  // ------------------------------------------------------------
  fastify.get<{ Params: { purchaseId: string } }>(
    "/:purchaseId/events",
    { preHandler: [fastify.authenticate] },
    async (request, reply) => {
      const orgId = requireOrgId(request, reply);
      if (!orgId) return;

      const actorId = requireActorId(request, reply);
      if (!actorId) return;

      const role = getRole(request);
      const { purchaseId } = request.params;

      const client = await fastify.pg.connect();
      try {
        await client.query("BEGIN");
        await client.query("SET LOCAL TIME ZONE 'UTC'");
        await setPgContext(client, {
          organizationId: orgId,
          userId: actorId,
          role,
        });

        
      await assertRlsContextWithUser(client);
const { rows } = await client.query(
          `
          select
            id::text as id,
            event_type::text as event_type,
            actor_user_id::text as actor_user_id,
            from_status,
            to_status,
            note,
            metadata,
            (metadata->>'event_note') as event_note,
            created_at::text as created_at
          from public.purchase_events
          where organization_id = $1::uuid
            and purchase_id = $2::uuid
          order by created_at desc
          limit 100;
          `,
          [orgId, purchaseId]
        );

        await client.query("COMMIT");
        return reply.send({ ok: true, data: rows });
      } catch (e: any) {
        try { await client.query("ROLLBACK"); } catch {}
        request.log.error(e);
        return reply.code(400).send({ ok: false, error: "EVENTS_FAILED", message: e?.message || String(e) });
      } finally {
        client.release();
      }
    }
  );

  // ------------------------------------------------------------
  // POST /purchases/:purchaseId/pay ✅ protected + RLS-safe
  // ------------------------------------------------------------
  fastify.post<{
    Params: { purchaseId: string };
    Body: { paymentMethod: "card" | "bank_transfer" | "wallet"; amount?: number };
  }>(
    "/:purchaseId/pay",
    {
      preHandler: [fastify.authenticate],
      schema: {
        body: {
          type: "object",
          required: ["paymentMethod"],
          additionalProperties: false,
          properties: {
            paymentMethod: { type: "string", enum: ["card", "bank_transfer", "wallet"] },
            amount: { type: "number", minimum: 0 },
          },
        },
      },
    },
    async (request, reply) => {
      const orgId = requireOrgId(request, reply);
      if (!orgId) return;

      const actorId = requireActorId(request, reply);
      if (!actorId) return;

      const role = getRole(request);
      const { purchaseId } = request.params;
      const paymentMethod = request.body.paymentMethod;
      const amount = request.body.amount;

      const client = await fastify.pg.connect();
      try {
        await client.query("BEGIN");
        await client.query("SET LOCAL TIME ZONE 'UTC'");
        await setPgContext(client, {
          organizationId: orgId,
          userId: actorId,
          role,
        });

        
      await assertRlsContextWithUser(client);
const result = await payPropertyPurchase(client, {
          organizationId: orgId,
          purchaseId,
          paymentMethod,
          amount: typeof amount === "number" ? amount : undefined,
        });

        await client.query("COMMIT");
        return reply.send({ ok: true, data: result });
      } catch (err: any) {
        try { await client.query("ROLLBACK"); } catch {}
        return reply.code(400).send({
          ok: false,
          error: err?.code || "PAY_FAILED",
          message: err?.message || "Payment failed",
        });
      } finally {
        client.release();
      }
    }
  );

  // ------------------------------------------------------------
  // POST /purchases/:purchaseId/escrow/hold ✅ protected + RLS-safe
  // ------------------------------------------------------------
  fastify.post<{
    Params: { purchaseId: string };
    Body: { amount: number; note?: string };
  }>(
    "/:purchaseId/escrow/hold",
    {
      preHandler: [fastify.authenticate],
      schema: {
        body: {
          type: "object",
          required: ["amount"],
          additionalProperties: false,
          properties: {
            amount: { type: "number", minimum: 0 },
            note: { type: "string", minLength: 1 },
          },
        },
      },
    },
    async (request, reply) => {
      const orgId = requireOrgId(request, reply);
      if (!orgId) return;

      const actorId = requireActorId(request, reply);
      if (!actorId) return;

      const role = getRole(request);
      const { purchaseId } = request.params;

      const amount = Number(request.body.amount);
      const note = (request.body.note ?? null) as string | null;

      // Treat request.amount as DELTA, convert to NEW TOTAL for DB function
      let newTotalHeld = 0;

      const client = await fastify.pg.connect();
      try {
        await client.query("BEGIN");
        await client.query("SET LOCAL TIME ZONE 'UTC'");
        await setPgContext(client, {
          organizationId: orgId,
          userId: actorId,
          role,
          eventNote: note,
        });

        
        await assertRlsContextWithUser(client);
        const purchase = await fetchPurchaseOr404(client, purchaseId, orgId);
        if (!purchase) {
          await client.query("ROLLBACK");
          return reply.code(404).send({ ok: false, error: "NOT_FOUND", message: "Purchase not found" });
        }

        const currentHeld = Number((purchase as any)?.escrow_held_amount ?? 0);
        newTotalHeld = currentHeld + amount;


        await client.query(
          `select public.purchase_escrow_hold($1::uuid, $2::uuid, $3::numeric, $4::text, $5::text);`,
          [purchaseId, orgId, newTotalHeld, purchase.currency, note ?? "escrow hold"]
        );

        const after = await fetchPurchaseOr404(client, purchaseId, orgId);
        await client.query("COMMIT");

        return reply.send({
          ok: true,
          data: {
            ok: true,
            held: true,
            purchase: after
              ? {
                  id: after.id,
                  escrow_wallet_account_id: after.escrow_wallet_account_id ?? null,
                  escrow_held_amount: String(after.escrow_held_amount ?? 0),
                  currency: after.currency,
                }
              : null,
          },
        });
      } catch (err: any) {
        try { await client.query("ROLLBACK"); } catch {}
        return reply.code(400).send({
          ok: false,
          error: err?.code || "ESCROW_HOLD_FAILED",
          message: err?.message || "Escrow hold failed",
        });
      } finally {
        client.release();
      }
    }
  );

  // ------------------------------------------------------------
  // POST /purchases/:purchaseId/escrow/release ✅ protected + RLS-safe
  // ------------------------------------------------------------
  fastify.post<{
    Params: { purchaseId: string };
    Body: { amount: number; platformFeeAmount?: number; note?: string };
  }>(
    "/:purchaseId/escrow/release",
    {
      preHandler: [fastify.authenticate],
      schema: {
        body: {
          type: "object",
          required: ["amount"],
          additionalProperties: false,
          properties: {
            amount: { type: "number", minimum: 0 },
            platformFeeAmount: { type: "number", minimum: 0 },
            note: { type: "string", minLength: 1 },
          },
        },
      },
    },
    async (request, reply) => {
      const orgId = requireOrgId(request, reply);
      if (!orgId) return;

      const actorId = requireActorId(request, reply);
      if (!actorId) return;

      const role = getRole(request);
      const { purchaseId } = request.params;

      const amount = Number(request.body.amount);
      const platformFeeAmountFromClient = Number(request.body.platformFeeAmount ?? 0);
      

      const note = (request.body.note ?? null) as string | null;

      const client = await fastify.pg.connect();
      try {
        await client.query("BEGIN");
        await client.query("SET LOCAL TIME ZONE 'UTC'");
        await setPgContext(client, {
          organizationId: orgId,
          userId: actorId,
          role,
          eventNote: note,
        });

        
        await assertRlsContextWithUser(client);
        const purchase = await fetchPurchaseOr404(client, purchaseId, orgId);
        if (!purchase) {
          await client.query("ROLLBACK");
          return reply.code(404).send({ ok: false, error: "NOT_FOUND", message: "Purchase not found" });
        }

        if (!purchase.escrow_wallet_account_id) {
          await client.query("ROLLBACK");
          return escrowInvariantError(reply, "ESCROW_NOT_OPEN", "Cannot release: escrow wallet not set.");
        }

        const held = Number(purchase.escrow_held_amount ?? 0);
        const currentReleased = Number((purchase as any).escrow_released_amount ?? 0);
        const newTotalRelease = currentReleased + amount;

        // ✅ Server-side fee (do NOT trust client for platform fees)
        // Fee is computed on the RELEASE DELTA (amount)
        const split = computePlatformFeeSplit({
          paymentKind: "buy",
          amount,
          currency: purchase.currency,
        });
        const platformFeeAmount = Number(split.platformFee ?? 0);

        // (optional) log/keep client value for debugging
        void platformFeeAmountFromClient;


        if (held < newTotalRelease) {
          await client.query("ROLLBACK");
          return reply.code(400).send({
            ok: false,
            error: "ESCROW_RELEASE_TOO_HIGH",
            message: `Cannot release ${amount} because held is ${held}`,
          });
        }

        await client.query(
          `select public.purchase_escrow_release($1::uuid, $2::uuid, $3::numeric, $4::text, $5::numeric, $6::text);`,
          [purchaseId, orgId, newTotalRelease, purchase.currency, platformFeeAmount, note ?? "escrow release"]
        );

        const after = await fetchPurchaseOr404(client, purchaseId, orgId);
        await client.query("COMMIT");

        return reply.send({
          ok: true,
          data: {
            ok: true,
            released: true,
            purchase: after
              ? {
                  id: after.id,
                  escrow_released_amount: String(after.escrow_released_amount ?? 0),
                  escrow_released_at: after.escrow_released_at ?? null,
                  currency: after.currency,
                }
              : null,
          },
        });
      } catch (err: any) {
        try { await client.query("ROLLBACK"); } catch {}
        return reply.code(400).send({
          ok: false,
          error: err?.code || "ESCROW_RELEASE_FAILED",
          message: err?.message || "Escrow release failed",
        });
      } finally {
        client.release();
      }
    }
  );

  // ------------------------------------------------------------
  // POST /purchases/:purchaseId/status ✅ protected + RLS-safe
  // ------------------------------------------------------------
  fastify.post<{
    Params: { purchaseId: string };
    Body: { status: string; note?: string; autoEscrow?: boolean; platformFeeAmount?: number };
  }>(
    "/:purchaseId/status",
    {
      preHandler: [fastify.authenticate],
      schema: {
        body: {
          type: "object",
          required: ["status"],
          additionalProperties: false,
          properties: {
            status: { type: "string", minLength: 1 },
            note: { type: "string", minLength: 1 },
            autoEscrow: { type: "boolean" },
            platformFeeAmount: { type: "number", minimum: 0 },
          },
        },
      },
    },
    async (request, reply) => {
      const orgId = requireOrgId(request, reply);
      if (!orgId) return;

      const actorId = requireActorId(request, reply);
      if (!actorId) return;

      const role = getRole(request);

      const { purchaseId } = request.params;
      const newStatus = String(request.body.status || "");
      const note = (request.body.note ?? null) as string | null;
      const autoEscrow = Boolean(request.body.autoEscrow ?? false);
      const platformFeeAmountFromClient = Number(request.body.platformFeeAmount ?? 0);

      const client = await fastify.pg.connect();
      try {
        await client.query("BEGIN");
        await client.query("SET LOCAL TIME ZONE 'UTC'");
        await setPgContext(client, {
          organizationId: orgId,
          userId: actorId,
          role,
          eventNote: note,
        });

        
      await assertRlsContextWithUser(client);
const { rows } = await client.query(
          `
          update public.property_purchases
          set status = $3::purchase_status,
              updated_at = now()
          where id = $1::uuid
            and organization_id = $2::uuid
            and deleted_at is null
          returning id::text;
          `,
          [purchaseId, orgId, newStatus]
        );

        if (!rows?.[0]) {
          await client.query("ROLLBACK");
          return reply.code(404).send({ ok: false, error: "NOT_FOUND", message: "Purchase not found" });
        }

        // auto escrow logic (unchanged)
        if (autoEscrow) {
          if (newStatus === "escrow_opened" || newStatus === "deposit_paid") {
            const refreshed = await fetchPurchaseOr404(client, purchaseId, orgId);
            if (!refreshed) {
              await client.query("ROLLBACK");
              return reply.code(404).send({ ok: false, error: "NOT_FOUND", message: "Purchase not found" });
            }

            const deposit =
              Number(refreshed.deposit_amount ?? 0) > 0
                ? Number(refreshed.deposit_amount ?? 0)
                : Number(refreshed.earnest_deposit_amount ?? 0);

            const alreadyHeld = Number(refreshed.escrow_held_amount ?? 0);

            if (deposit > 0 && alreadyHeld < deposit) {
              await client.query(
                `select public.purchase_escrow_hold($1::uuid, $2::uuid, $3::numeric, $4::text, $5::text);`,
                // DB function expects NEW TOTAL held
                [purchaseId, orgId, deposit, refreshed.currency, note ?? "auto escrow hold"]
              );
            }
          }

          if (newStatus === "closed") {
            const refreshed = await fetchPurchaseOr404(client, purchaseId, orgId);
            if (!refreshed) {
              await client.query("ROLLBACK");
              return reply.code(404).send({ ok: false, error: "NOT_FOUND", message: "Purchase not found" });
            }

            const held = Number(refreshed.escrow_held_amount ?? 0);
            const alreadyReleased = Number(refreshed.escrow_released_amount ?? 0);
            const escrowWalletId = refreshed.escrow_wallet_account_id ?? null;

            if (held > 0) {
              if (!escrowWalletId) {
                await client.query("ROLLBACK");
                return escrowInvariantError(reply, "ESCROW_NOT_OPEN", "Cannot auto-release: escrow wallet not set.");
              }

              if (held > alreadyReleased) {
                // ✅ Server-side platform fee (do NOT trust client)
                // For auto-release we are releasing the remaining DELTA:
                const releaseDelta = Math.max(0, held - alreadyReleased);
                const split = computePlatformFeeSplit({
                  paymentKind: "buy",
                  amount: releaseDelta,
                  currency: refreshed.currency,
                });
                const platformFeeAmount = Number(split.platformFee ?? 0);


                await client.query(
                  `select public.purchase_escrow_release($1::uuid, $2::uuid, $3::numeric, $4::text, $5::numeric, $6::text);`,
                  // DB function expects NEW TOTAL released
                  [purchaseId, orgId, held, refreshed.currency, platformFeeAmount, note ?? "auto escrow release"]
                );
              }
            }
          }
        }

        const final = await fetchPurchaseOr404(client, purchaseId, orgId);
        await client.query("COMMIT");

        return reply.send({ ok: true, data: { purchase: final, note, autoEscrow } });
      } catch (err: any) {
        try { await client.query("ROLLBACK"); } catch {}
        return reply.code(400).send({
          ok: false,
          error: err?.code || "STATUS_UPDATE_FAILED",
          message: err?.message || "Status update failed",
        });
      } finally {
        client.release();
      }
    }
  );

  // ------------------------------------------------------------
  // POST /purchases/:purchaseId/refund ✅ protected + RLS-safe
  // ------------------------------------------------------------
  fastify.post<{
    Params: { purchaseId: string };
    Body: {
      refundMethod: "card" | "bank_transfer" | "wallet";
      amount: number;
      reason?: string;
      refundPaymentId: string;
    };
  }>(
    "/:purchaseId/refund",
    {
      preHandler: [fastify.authenticate],
      schema: {
        body: {
          type: "object",
          required: ["refundMethod", "amount", "refundPaymentId"],
          additionalProperties: false,
          properties: {
            refundMethod: { type: "string", enum: ["card", "bank_transfer", "wallet"] },
            amount: { type: "number", minimum: 0 },
            reason: { type: "string", minLength: 1 },
            refundPaymentId: { type: "string", format: "uuid" },
          },
        },
      },
    },
    async (request, reply) => {
      const orgId = requireOrgId(request, reply);
      if (!orgId) return;

      const actorId = requireActorId(request, reply);
      if (!actorId) return;

      const role = getRole(request);

      const { purchaseId } = request.params;
      const refundMethod = request.body.refundMethod;
      const amount = request.body.amount;
      const reason = request.body.reason ?? null;
      const refundPaymentId = request.body.refundPaymentId;

      const client = await fastify.pg.connect();
      try {
        await client.query("BEGIN");
        await client.query("SET LOCAL TIME ZONE 'UTC'");
        await setPgContext(client, {
          organizationId: orgId,
          userId: actorId,
          role,
          eventNote: reason,
        });

        
      await assertRlsContextWithUser(client);
const result = await refundPropertyPurchase(client, {
          organizationId: orgId,
          purchaseId,
          amount,
          refundMethod,
          reason,
          refundPaymentId,
          refundedBy: actorId,
        });

        await client.query("COMMIT");
        return reply.send({ ok: true, data: result });
      } catch (err: any) {
        try { await client.query("ROLLBACK"); } catch {}
        return reply.code(400).send({
          ok: false,
          error: err?.code || "REFUND_FAILED",
          message: err?.message || "Refund failed",
        });
      } finally {
        client.release();
      }
    }
  );
}