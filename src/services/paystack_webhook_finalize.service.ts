// src/services/paystack_webhook_finalize.service.ts
import type { PoolClient } from "pg";
import { computePlatformFeeSplit } from "../config/fees.config.js";

type PaystackEvent = {
  event?: string;
  data?: {
    reference?: string;
    amount?: number; // lowest unit
    currency?: string;
    id?: number | string;
  };
};

function lowestUnitToMajor(amount: number): number {
  // NGN kobo -> naira, USD cents -> dollars
  return Math.round((amount / 100) * 100) / 100;
}

async function resolvePayeeUserIdForPayment(
  client: PoolClient,
  payment: { reference_type: string | null; reference_id: string | null; property_id: string }
): Promise<string> {
  const refType = String(payment.reference_type || "");
  const refId = payment.reference_id;

  if (refType === "rent_invoice" && refId) {
    const r = await client.query<{ payee_user_id: string }>(
      `
      SELECT p.owner_id AS payee_user_id
      FROM public.rent_invoices ri
      JOIN public.properties p ON p.id = ri.property_id
      WHERE ri.id = $1::uuid
        AND ri.deleted_at IS NULL
      LIMIT 1;
      `,
      [refId]
    );
    const payee = r.rows[0]?.payee_user_id;
    if (!payee) throw new Error("Cannot resolve payee for rent_invoice " + refId);
    return payee;
  }

  if (refType === "purchase" && refId) {
    const r = await client.query<{ payee_user_id: string }>(
      `
      SELECT pp.seller_id AS payee_user_id
      FROM public.property_purchases pp
      WHERE pp.id = $1::uuid
        AND pp.deleted_at IS NULL
      LIMIT 1;
      `,
      [refId]
    );
    const payee = r.rows[0]?.payee_user_id;
    if (!payee) throw new Error("Cannot resolve payee for purchase " + refId);
    return payee;
  }

  throw new Error(`Unsupported reference_type=${refType}. Add resolver branch.`);
}

export async function finalizePaystackChargeSuccess(
  client: PoolClient,
  event: PaystackEvent
): Promise<{ ok: true; alreadyProcessed: boolean } | { ok: false; error: string; message?: string }> {

  const reference = String(event?.data?.reference || "").trim();
  if (!reference) return { ok: false, error: "MISSING_REFERENCE" };

  // 2) Lock the payment row so webhook retries don’t double-process
  const pRes = await client.query<{
    id: string;
    amount: string;
    currency: string | null;
    status: string | null;
    transaction_reference: string;
    reference_type: string | null;
    reference_id: string | null;
    property_id: string;
  }>(
    `
    SELECT
      id::text,
      amount::text,
      currency,
      status::text,
      transaction_reference,
      reference_type::text,
      reference_id::text,
      property_id::text
    FROM public.payments
    WHERE transaction_reference = $1
      AND deleted_at IS NULL
    LIMIT 1
    FOR UPDATE;
    `,
    [reference]
  );

  const payment = pRes.rows[0];
  if (!payment) return { ok: false, error: "PAYMENT_NOT_FOUND" };

  if (payment.status === "successful") {
    return { ok: true, alreadyProcessed: true };
  }

  // 3) Optional sanity check: Paystack amount is in lowest unit
  const paymentAmount = Number(payment.amount);
  const evAmt = typeof event?.data?.amount === "number" ? lowestUnitToMajor(event.data.amount) : null;

  if (evAmt != null && Number(evAmt) !== Number(paymentAmount)) {
    return { ok: false, error: "AMOUNT_MISMATCH", message: `event=${evAmt} payment=${paymentAmount}` };
  }

  const currency = (payment.currency ?? event?.data?.currency ?? "USD") || "USD";

  // 4) Resolve payment kind (rent / buy / subscription)
  const paymentKind =
    payment.reference_type === "purchase" ? "buy"
    : payment.reference_type === "rent_invoice" ? "rent"
    : "rent";

  // 5) Compute fee split in CODE (fees.config.ts)
  const split = computePlatformFeeSplit({
    paymentKind,
    amount: paymentAmount,
    currency,
  });

  // 6) Write fee amounts to payments row FIRST (DB reads these later)
  await client.query(
    `
    UPDATE public.payments
    SET
      platform_fee_amount = $2::numeric(15,2),
      payee_amount        = $3::numeric(15,2),
      updated_at          = NOW()
    WHERE id = $1::uuid;
    `,
    [payment.id, split.platformFee, split.payeeNet]
  );

  // 7) Ensure splits exist (DB will insert platform_fee + payee using payment columns)
  await client.query(
    `SELECT public.ensure_payment_splits($1::uuid);`,
    [payment.id]
  );

  // 8) Flip to successful LAST (trigger credits wallets)
  await client.query(
    `
    UPDATE public.payments
    SET
      status = 'successful'::payment_status,
      completed_at = NOW(),
      gateway_transaction_id = COALESCE(gateway_transaction_id, $2::text),
      gateway_response = COALESCE(gateway_response, $3::jsonb),
      updated_at = NOW()
    WHERE id = $1::uuid;
    `,
    [payment.id, event?.data?.id != null ? String(event.data.id) : null, JSON.stringify(event ?? {})]
  );

  return { ok: true, alreadyProcessed: false };
}