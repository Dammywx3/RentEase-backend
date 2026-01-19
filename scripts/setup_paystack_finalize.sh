#!/usr/bin/env bash
set -euo pipefail

echo "== RentEase: Paystack finalize (splits + status -> trigger credits) =="

# -----------------------------
# 1) Service: paystack_finalize
# -----------------------------
mkdir -p src/services

cat > src/services/paystack_finalize.service.ts <<'TS'
import type { PoolClient } from "pg";
import { computePlatformFeeSplit } from "../config/fees.config.js";

type PaystackEvent = {
  event?: string;
  data?: {
    reference?: string;
    id?: number | string;
    amount?: number;   // usually minor units (kobo)
    currency?: string; // e.g. "NGN"
    status?: string;
  };
};

type PaymentRow = {
  id: string;
  tenant_id: string;
  listing_id: string;
  property_id: string;
  amount: string;
  currency: string | null;
  status: string | null;
  reference_type: string | null;
  reference_id: string | null;
};

function approxEqual(a: number, b: number, eps = 0.01) {
  return Math.abs(a - b) <= eps;
}

export async function finalizePaystackChargeSuccess(
  client: PoolClient,
  evt: PaystackEvent
): Promise<{ ok: true } | { ok: false; error: string; message?: string }> {
  if ((evt.event ?? "") !== "charge.success") return { ok: true };

  const reference = String(evt.data?.reference ?? "").trim();
  if (!reference) return { ok: false, error: "MISSING_REFERENCE" };

  // 1) Find payment by transaction_reference
  const payRes = await client.query<PaymentRow>(
    `
    SELECT
      id::text,
      tenant_id::text,
      listing_id::text,
      property_id::text,
      amount::text,
      currency,
      status::text,
      reference_type::text,
      reference_id::text
    FROM public.payments
    WHERE transaction_reference = $1
      AND deleted_at IS NULL
    LIMIT 1;
    `,
    [reference]
  );

  const payment = payRes.rows[0];
  if (!payment) {
    return { ok: false, error: "PAYMENT_NOT_FOUND", message: `reference=${reference}` };
  }

  if ((payment.status ?? "").toLowerCase() === "successful") {
    return { ok: true }; // idempotent
  }

  const amountMajor = Number(payment.amount);
  const currency = (payment.currency ?? evt.data?.currency ?? "USD") || "USD";

  // Optional sanity check vs paystack amount (often minor units)
  const psAmount = typeof evt.data?.amount === "number" ? evt.data.amount : null;
  if (psAmount != null) {
    const major = psAmount / 100;
    const okMatch = approxEqual(amountMajor, major) || approxEqual(amountMajor, psAmount);
    if (!okMatch) {
      return {
        ok: false,
        error: "AMOUNT_MISMATCH",
        message: `payments.amount=${amountMajor} vs paystack.amount=${psAmount} (major=${major})`,
      };
    }
  }

  // 2) Resolve org + payee depending on reference_type
  let orgId: string | null = null;
  let payeeUserId: string | null = null;

  if (payment.reference_type === "rent_invoice" && payment.reference_id) {
    const r = await client.query<{ organization_id: string; payee_user_id: string }>(
      `
      SELECT
        ri.organization_id::text AS organization_id,
        p.owner_id::text AS payee_user_id
      FROM public.rent_invoices ri
      JOIN public.properties p ON p.id = ri.property_id
      WHERE ri.id = $1::uuid
        AND ri.deleted_at IS NULL
      LIMIT 1;
      `,
      [payment.reference_id]
    );
    orgId = r.rows[0]?.organization_id ?? null;
    payeeUserId = r.rows[0]?.payee_user_id ?? null;
  } else if (payment.reference_type === "purchase" && payment.reference_id) {
    const r = await client.query<{ organization_id: string; payee_user_id: string }>(
      `
      SELECT
        pp.organization_id::text AS organization_id,
        pp.seller_id::text AS payee_user_id
      FROM public.property_purchases pp
      WHERE pp.id = $1::uuid
        AND pp.deleted_at IS NULL
      LIMIT 1;
      `,
      [payment.reference_id]
    );
    orgId = r.rows[0]?.organization_id ?? null;
    payeeUserId = r.rows[0]?.payee_user_id ?? null;
  } else {
    return {
      ok: false,
      error: "UNSUPPORTED_REFERENCE_TYPE",
      message: `reference_type=${payment.reference_type}`,
    };
  }

  if (!orgId || !payeeUserId) return { ok: false, error: "PAYEE_RESOLVE_FAILED" };

  // Ensure org context for defaults/policies
  await client.query("select set_config('app.organization_id', $1, true)", [orgId]);

  // 3) Compute split
  const split = computePlatformFeeSplit({
    paymentKind: payment.reference_type === "purchase" ? "buy" : "rent",
    amount: amountMajor,
    currency,
  });

  // 4) Insert splits idempotently
  await client.query(
    `
    INSERT INTO public.payment_splits (
      payment_id, split_type, beneficiary_kind, beneficiary_user_id, amount, currency
    )
    SELECT
      $1::uuid,
      'platform_fee'::public.split_type,
      'platform'::public.beneficiary_kind,
      NULL,
      $2::numeric,
      $3::text
    WHERE NOT EXISTS (
      SELECT 1 FROM public.payment_splits
      WHERE payment_id = $1::uuid AND split_type = 'platform_fee'::public.split_type
    );
    `,
    [payment.id, split.platformFee, currency]
  );

  await client.query(
    `
    INSERT INTO public.payment_splits (
      payment_id, split_type, beneficiary_kind, beneficiary_user_id, amount, currency
    )
    SELECT
      $1::uuid,
      'payee'::public.split_type,
      'user'::public.beneficiary_kind,
      $2::uuid,
      $3::numeric,
      $4::text
    WHERE NOT EXISTS (
      SELECT 1 FROM public.payment_splits
      WHERE payment_id = $1::uuid AND split_type = 'payee'::public.split_type
    );
    `,
    [payment.id, payeeUserId, split.payeeNet, currency]
  );

  // Optional: rent invoice linking + mark paid
  if (payment.reference_type === "rent_invoice" && payment.reference_id) {
    await client.query(
      `
      INSERT INTO public.invoice_payments (invoice_id, payment_id, amount)
      VALUES ($1::uuid, $2::uuid, $3::numeric)
      ON CONFLICT DO NOTHING;
      `,
      [payment.reference_id, payment.id, amountMajor]
    );

    await client.query(
      `
      UPDATE public.rent_invoices ri
      SET
        paid_amount = COALESCE(ri.paid_amount, 0) + $1::numeric,
        paid_at = NOW(),
        status = CASE
          WHEN (COALESCE(ri.paid_amount, 0) + $1::numeric) >= ri.total_amount
            THEN 'paid'::public.invoice_status
          ELSE ri.status
        END,
        updated_at = NOW()
      WHERE ri.id = $2::uuid
        AND ri.deleted_at IS NULL;
      `,
      [amountMajor, payment.reference_id]
    );
  }

  // 5) Update payment to successful AFTER splits exist
  // This triggers wallet_credit_from_splits(payment_id)
  await client.query(
    `
    UPDATE public.payments
    SET
      status = 'successful'::public.payment_status,
      completed_at = NOW(),
      gateway_transaction_id = COALESCE(gateway_transaction_id, $2::text),
      gateway_response = COALESCE(gateway_response, $3::jsonb),
      platform_fee_amount = $4::numeric,
      payee_amount = $5::numeric,
      currency = COALESCE(currency, $6::text),
      updated_at = NOW()
    WHERE id = $1::uuid;
    `,
    [
      payment.id,
      String(evt.data?.id ?? ""),
      JSON.stringify(evt),
      split.platformFee,
      split.payeeNet,
      currency,
    ]
  );

  return { ok: true };
}
TS

echo "✅ Wrote: src/services/paystack_finalize.service.ts"

# -----------------------------
# 2) Overwrite webhook route
# -----------------------------
mkdir -p src/routes

cat > src/routes/webhooks.ts <<'TS'
import type { FastifyInstance } from "fastify";
import crypto from "node:crypto";
import { paymentConfig } from "../config/payment.config.js";
import { finalizePaystackChargeSuccess } from "../services/paystack_finalize.service.js";

export async function webhooksRoutes(app: FastifyInstance) {
  app.post(
    "/webhooks/paystack",
    {
      // fastify-raw-body reads this and attaches request.rawBody
      config: { rawBody: true },
    },
    async (request, reply) => {
      const secret = paymentConfig.paystack.webhookSecret;
      const signature = String((request.headers["x-paystack-signature"] ?? "")).trim();

      if (!signature) {
        return reply.code(400).send({ ok: false, error: "SIGNATURE_MISSING" });
      }

      const raw = (request as any).rawBody as Buffer | undefined;
      if (!raw || !Buffer.isBuffer(raw)) {
        return reply.code(500).send({ ok: false, error: "RAW_BODY_MISSING" });
      }

      const hash = crypto.createHmac("sha512", secret).update(raw).digest("hex");
      if (hash !== signature) {
        return reply.code(401).send({ ok: false, error: "INVALID_SIGNATURE" });
      }

      let event: any;
      try {
        event = JSON.parse(raw.toString("utf8"));
      } catch {
        return reply.code(400).send({ ok: false, error: "INVALID_JSON" });
      }

      // ✅ Verified event
      app.log.info({ event: event?.event, dataRef: event?.data?.reference }, "paystack webhook received");

      // Finalize in DB transaction (create splits -> set payments.successful -> trigger credits)
      // @ts-ignore - fastify-postgres decorates app.pg
      const pg = await app.pg.connect();
      try {
        await pg.query("BEGIN");
        const res = await finalizePaystackChargeSuccess(pg, event);
        if (!res.ok) {
          app.log.warn({ error: res.error, message: res.message }, "paystack finalize skipped/failed");
        }
        await pg.query("COMMIT");
      } catch (e) {
        try { await pg.query("ROLLBACK"); } catch {}
        app.log.error(e, "paystack finalize failed");
        // still return 200 to avoid repeated Paystack retries storm
      } finally {
        pg.release();
      }

      return reply.send({ ok: true });
    }
  );
}
TS

echo "✅ Wrote: src/routes/webhooks.ts"

# -----------------------------
# 3) Ensure webhooksRoutes registered once
# -----------------------------
if [ -f src/routes/index.ts ]; then
  # Keep only first "register(webhooksRoutes)" occurrence
  perl -i -ne '
    if (/register\(webhooksRoutes\)/) { $c++; print if $c==1; next; }
    print;
  ' src/routes/index.ts
  echo "✅ Deduped webhooksRoutes registration in src/routes/index.ts"
else
  echo "⚠️ src/routes/index.ts not found (skipping dedupe)."
fi

echo ""
echo "== Setup complete =="
echo "Now run:"
echo '  PAYSTACK_SECRET_KEY="sk_test_..." npm run dev'
echo ""
echo "Typecheck:"
echo "  npm run typecheck 2>/dev/null || npx tsc -p tsconfig.json --noEmit"
