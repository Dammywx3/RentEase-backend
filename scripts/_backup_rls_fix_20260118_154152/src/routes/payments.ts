import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { setPgContext } from "../db/set_pg_context.js";

import {
  createRentInvoicePaymentIntent,
  finalizePaystackSuccessForRentInvoice,
} from "../services/rent_invoice_payments.service.js";

export async function paymentsRoutes(app: FastifyInstance) {
  // -------------------------------
  // Create rent-invoice payment intent (AUTH)
  // POST /v1/rent-invoices/:id/payments/intent
  // -------------------------------
  app.post(
    "/rent-invoices/:id/payments/intent",
    { preHandler: [app.authenticate] },
    async (req, reply) => {
      const params = z.object({ id: z.string().uuid() }).parse((req as any).params);
      const body = z
        .object({
          paymentMethod: z.string().default("card"),
          amount: z.number().optional().nullable(),
          currency: z.string().optional().nullable(),
        })
        .default({ paymentMethod: "card" })
        .parse((req as any).body ?? { paymentMethod: "card" });

      const organizationId = String((req as any).orgId ?? "").trim();
      const userId = String((req as any).user?.userId ?? "").trim();

      if (!organizationId) {
        return reply
          .code(400)
          .send({ ok: false, error: "ORG_REQUIRED", message: "Missing orgId from auth middleware" });
      }
      if (!userId) {
        return reply
          .code(401)
          .send({ ok: false, error: "UNAUTHORIZED", message: "Missing authenticated user" });
      }

      const pgAny: any = (app as any).pg;
      if (!pgAny?.connect) {
        return reply.code(500).send({
          ok: false,
          error: "PG_NOT_CONFIGURED",
          message: "Fastify postgres plugin not found at app.pg",
        });
      }

      const client = await pgAny.connect();
      try {
        await client.query("BEGIN");

        // ✅ RLS context
        await client.query("select set_config('app.organization_id', $1, true)", [organizationId]);
        await client.query("select set_config('request.header.x_organization_id', $1, true)", [organizationId]);
        await client.query("select set_config('request.jwt.claim.sub', $1, true)", [userId]);
        await client.query("select set_config('app.user_id', $1, true)", [userId]);

        const intent = await createRentInvoicePaymentIntent(client, {
          organizationId,
          invoiceId: params.id,
          paymentMethod: body.paymentMethod,
          amount: body.amount ?? null,
          currency: body.currency ?? null,
        });

        await client.query("COMMIT");
        return reply.send({ ok: true, data: intent });
      } catch (err: any) {
        try {
          await client.query("ROLLBACK");
        } catch {}
        return reply.code(400).send({
          ok: false,
          error: err?.code ?? "BAD_REQUEST",
          message: err?.message ?? String(err),
        });
      } finally {
        client.release();
      }
    }
  );

  // ---------------------------------------------------------
  // OPTIONAL: Manual finalize endpoint (AUTH)
  // Use only for debugging when webhook isn't firing yet.
  // POST /v1/payments/paystack/finalize
  // body: { transactionReference, gatewayTransactionId?, gatewayResponse? }
  // ---------------------------------------------------------
  app.post(
    "/payments/paystack/finalize",
    { preHandler: [app.authenticate] },
    async (req, reply) => {
      const body = z
        .object({
          transactionReference: z.string().min(5),
          gatewayTransactionId: z.string().optional().nullable(),
          gatewayResponse: z.any().optional(),
        })
        .parse((req as any).body);

      const organizationId = String((req as any).orgId ?? "").trim();
      const userId = String((req as any).user?.userId ?? "").trim();

      if (!organizationId) {
        return reply
          .code(400)
          .send({ ok: false, error: "ORG_REQUIRED", message: "Missing orgId from auth middleware" });
      }
      if (!userId) {
        return reply
          .code(401)
          .send({ ok: false, error: "UNAUTHORIZED", message: "Missing authenticated user" });
      }

      const pgAny: any = (app as any).pg;
      const client = await pgAny.connect();

      try {
        await client.query("BEGIN");

        // ✅ RLS context
        await client.query("select set_config('app.organization_id', $1, true)", [organizationId]);
        await client.query("select set_config('request.header.x_organization_id', $1, true)", [organizationId]);
        await client.query("select set_config('request.jwt.claim.sub', $1, true)", [userId]);
        await client.query("select set_config('app.user_id', $1, true)", [userId]);

        const res = await finalizePaystackSuccessForRentInvoice(client, {
          transactionReference: body.transactionReference,
          gatewayTransactionId: body.gatewayTransactionId ?? null,
          gatewayResponse: body.gatewayResponse ?? null,
        });

        await client.query("COMMIT");
        return reply.send({ ok: true, data: res });
      } catch (err: any) {
        try {
          await client.query("ROLLBACK");
        } catch {}
        return reply.code(400).send({
          ok: false,
          error: err?.code ?? "BAD_REQUEST",
          message: err?.message ?? String(err),
        });
      } finally {
        client.release();
      }
    }
  );
}