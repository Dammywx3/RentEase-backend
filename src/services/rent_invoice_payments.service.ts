// src/services/rent_invoice_payments.service.ts
import type { PoolClient } from "pg";
import { setPgContext } from "../db/set_pg_context.js";
import { randomUUID, createHmac, timingSafeEqual } from "crypto";
import { computePlatformFeeSplit } from "../config/fees.config.js";

type RentInvoiceMini = {
  id: string;
  organization_id: string;
  tenancy_id: string;
  tenant_id: string;
  property_id: string;
  total_amount: string;
  paid_amount: string | null;
  currency: string | null;
  deleted_at: string | null;
  status: string;
  listing_id: string | null;
};

type PaymentRow = {
  id: string;
  tenant_id: string;
  listing_id: string;
  property_id: string;
  amount: string;
  currency: string | null;
  status: string;
  transaction_reference: string;
  payment_method: string;
  reference_type: string | null;
  reference_id: string | null;
};

type EnumMaps = {
  splitTypePlatform: string;
  splitTypePayee: string;
  beneficiaryKindPlatform: string;
  beneficiaryKindUser: string;
};

async function loadEnumValues(client: PoolClient): Promise<EnumMaps> {
  // Discover enum values safely (so we don't guess wrong and crash).
  // We pick the "best" matching labels from what exists in your DB.
  const splitTypes = await client.query<{ v: string }>(
    "select unnest(enum_range(null::public.split_type))::text as v"
  );
  const beneficiaryKinds = await client.query<{ v: string }>(
    "select unnest(enum_range(null::public.beneficiary_kind))::text as v"
  );

  const st = splitTypes.rows.map((r) => r.v);
  const bk = beneficiaryKinds.rows.map((r) => r.v);

  const pick = (have: string[], candidates: string[], label: string) => {
    for (const c of candidates) if (have.includes(c)) return c;
    const e: any = new Error(
      `Cannot find a suitable enum value for ${label}. Have: [${have.join(", ")}], tried: [${candidates.join(", ")}]`
    );
    e.code = "ENUM_VALUE_MISSING";
    throw e;
  };

  return {
    splitTypePlatform: pick(st, ["platform_fee", "platform", "fee"], "split_type platform fee"),
    splitTypePayee: pick(st, ["payee", "payout", "net", "landlord"], "split_type payee net"),
    beneficiaryKindPlatform: pick(bk, ["platform"], "beneficiary_kind platform"),
    beneficiaryKindUser: pick(bk, ["user"], "beneficiary_kind user"),
  };
}

async function resolveRentInvoicePayeeUserId(
  client: PoolClient,
  invoiceId: string,
  organizationId: string
): Promise<string> {
  const r = await client.query<{ payee_user_id: string }>(
    `
    SELECT p.owner_id AS payee_user_id
    FROM public.rent_invoices ri
    JOIN public.properties p ON p.id = ri.property_id
    WHERE ri.id = $1::uuid
      AND ri.organization_id = $2::uuid
      AND ri.deleted_at IS NULL
    LIMIT 1;
    `,
    [invoiceId, organizationId]
  );

  const payee = r.rows[0]?.payee_user_id;
  if (!payee) {
    const e: any = new Error("Cannot resolve payee_user_id for invoice " + invoiceId);
    e.code = "PAYEE_NOT_FOUND";
    throw e;
  }
  return payee;
}

function toNum(n: string | number | null | undefined): number {
  if (n == null) return 0;
  return typeof n === "number" ? n : Number(n);
}

function round2(n: number): number {
  return Math.round((n + Number.EPSILON) * 100) / 100;
}

/**
 * Create a payment intent for a rent invoice
 * Inserts:
 *  - payments (pending)
 *  - payment_splits (platform fee + payee net)
 *
 * Does NOT mark invoice paid yet. That happens on webhook success.
 */
export async function createRentInvoicePaymentIntent(
  client: PoolClient,
  args: {
    organizationId: string;
    invoiceId: string;
    paymentMethod: "card" | "bank_transfer" | "wallet" | string;
    amount?: number | null; // defaults to remaining
    currency?: string | null; // optional override (normally uses invoice currency)
  }
): Promise<{
  paymentId: string;
  transactionReference: string;
  amount: number;
  currency: string;
}> {
  const inv = await client.query<RentInvoiceMini>(
    `
    SELECT
      ri.id::text,
      ri.organization_id::text,
      ri.tenancy_id::text,
      ri.tenant_id::text,
      ri.property_id::text,
      ri.total_amount::text,
      ri.paid_amount::text,
      ri.currency,
      ri.deleted_at::text,
      ri.status::text,
      t.listing_id::text AS listing_id
    FROM public.rent_invoices ri
    JOIN public.tenancies t ON t.id = ri.tenancy_id
    WHERE ri.id = $1::uuid
      AND ri.organization_id = $2::uuid
      AND ri.deleted_at IS NULL
    LIMIT 1;
    `,
    [args.invoiceId, args.organizationId]
  );

  const invoice = inv.rows[0];
  if (!invoice) {
    const e: any = new Error("Invoice not found");
    e.code = "INVOICE_NOT_FOUND";
    throw e;
  }

  if (!invoice.listing_id) {
    const e: any = new Error(
      `Tenancy (${invoice.tenancy_id}) has NULL listing_id. Cannot create payments row because payments.listing_id is required.`
    );
    e.code = "TENANCY_LISTING_REQUIRED";
    throw e;
  }

  const total = toNum(invoice.total_amount);
  const alreadyPaid = toNum(invoice.paid_amount);
  const remaining = round2(total - alreadyPaid);

  if (remaining <= 0) {
    const e: any = new Error("Invoice already fully paid");
    e.code = "INVOICE_ALREADY_PAID";
    throw e;
  }

  const amount = typeof args.amount === "number" ? round2(args.amount) : remaining;
  if (!(amount > 0)) {
    const e: any = new Error("Amount must be > 0");
    e.code = "AMOUNT_INVALID";
    throw e;
  }
  if (amount > remaining) {
    const e: any = new Error(`Amount (${amount}) exceeds remaining balance (${remaining})`);
    e.code = "AMOUNT_EXCEEDS_REMAINING";
    throw e;
  }

  const currency = (args.currency ?? invoice.currency ?? "USD") || "USD";
  const paymentMethod = args.paymentMethod || "card";

  const txRef = `rentinv_${invoice.id}_${randomUUID()}`;

  // create payments row (pending)
  const payRes = await client.query<{ id: string }>(
    `
    INSERT INTO public.payments (
      tenant_id,
      listing_id,
      property_id,
      amount,
      currency,
      status,
      transaction_reference,
      payment_method,
      reference_type,
      reference_id
    )
    VALUES (
      $1::uuid,
      $2::uuid,
      $3::uuid,
      $4::numeric,
      $5::varchar(3),
      'pending'::public.payment_status,
      $6::varchar(100),
      $7::public.payment_method,
      'rent_invoice',
      $8::uuid
    )
    RETURNING id::text;
    `,
    [
      invoice.tenant_id,
      invoice.listing_id,
      invoice.property_id,
      amount,
      currency,
      txRef,
      paymentMethod,
      invoice.id,
    ]
  );

  const paymentId = payRes.rows[0]?.id;
  if (!paymentId) {
    const e: any = new Error("Failed to create payment intent");
    e.code = "PAYMENT_CREATE_FAILED";
    throw e;
  }

  // compute fee split + insert payment_splits
  const split = computePlatformFeeSplit({
    paymentKind: "rent",
    amount,
    currency,
  });

  const payeeUserId = await resolveRentInvoicePayeeUserId(client, invoice.id, invoice.organization_id);
  const enums = await loadEnumValues(client);

  // Platform fee split
  await client.query(
    `
    INSERT INTO public.payment_splits (
      payment_id,
      split_type,
      beneficiary_kind,
      beneficiary_user_id,
      amount,
      currency
    )
    VALUES (
      $1::uuid,
      $2::public.split_type,
      $3::public.beneficiary_kind,
      NULL,
      $4::numeric,
      $5::varchar(3)
    );
    `,
    [paymentId, enums.splitTypePlatform, enums.beneficiaryKindPlatform, split.platformFee, currency]
  );

  // Payee net split
  await client.query(
    `
    INSERT INTO public.payment_splits (
      payment_id,
      split_type,
      beneficiary_kind,
      beneficiary_user_id,
      amount,
      currency
    )
    VALUES (
      $1::uuid,
      $2::public.split_type,
      $3::public.beneficiary_kind,
      $4::uuid,
      $5::numeric,
      $6::varchar(3)
    );
    `,
    [paymentId, enums.splitTypePayee, enums.beneficiaryKindUser, payeeUserId, split.payeeNet, currency]
  );

  return { paymentId, transactionReference: txRef, amount, currency };
}

/**
 * Finalize a payment after Paystack says "success":
 *  - Ensure fee split amounts exist on payments row
 *  - Ensure payment_splits exist (idempotent)
 *  - update payments.status -> successful (this triggers wallet_credit_from_splits via DB trigger)
 *  - link invoice_payments (invoice_id <-> payment_id)
 *  - update rent_invoices.paid_amount and mark paid when fully paid
 */
export async function finalizePaystackSuccessForRentInvoice(
  client: PoolClient,
  args: {
    transactionReference: string;
    gatewayTransactionId?: string | null;
    gatewayResponse?: any;
  }
): Promise<{ ok: boolean; reason?: string }> {
  // lock the payment row
  const p = await client.query<PaymentRow>(
    `
    SELECT
      id::text,
      tenant_id::text,
      listing_id::text,
      property_id::text,
      amount::text,
      currency,
      status::text,
      transaction_reference,
      payment_method::text,
      reference_type::text,
      reference_id::text
    FROM public.payments
    WHERE transaction_reference = $1
      AND deleted_at IS NULL
    LIMIT 1
    FOR UPDATE;
    `,
    [args.transactionReference]
  );

  const payment = p.rows[0];
  if (!payment) return { ok: false, reason: "PAYMENT_NOT_FOUND" };

  // Not a rent invoice payment? Just mark successful and return.
  // (But we keep it safe by not touching splits for unknown reference types.)
  if (payment.reference_type !== "rent_invoice" || !payment.reference_id) {
    await client.query(
      `
      UPDATE public.payments
      SET
        status = 'successful'::public.payment_status,
        gateway_transaction_id = COALESCE($2, gateway_transaction_id),
        gateway_response = COALESCE($3::jsonb, gateway_response),
        completed_at = COALESCE(completed_at, NOW()),
        updated_at = NOW()
      WHERE id = $1::uuid
        AND deleted_at IS NULL;
      `,
      [payment.id, args.gatewayTransactionId ?? null, args.gatewayResponse ?? null]
    );

    return { ok: true, reason: "NOT_RENT_INVOICE_REFERENCE" };
  }

  // -----------------------------
  // ✅ FIX: compute fee + ensure splits BEFORE status=successful (trigger runs on status)
  // -----------------------------
  const inv2 = await client.query<{ organization_id: string; currency: string | null }>(
    `
    SELECT ri.organization_id::text AS organization_id, ri.currency
    FROM public.rent_invoices ri
    WHERE ri.id = $1::uuid
      AND ri.deleted_at IS NULL
    LIMIT 1;
    `,
    [payment.reference_id]
  );

  const orgId = inv2.rows[0]?.organization_id ?? null;
  const currency = (payment.currency ?? inv2.rows[0]?.currency ?? "USD") || "USD";
  const amountMajor = Number(payment.amount);

  // Set org context for defaults/RLS helpers that rely on app.organization_id
  if (orgId) {
    
await setPgContext(client, { organizationId: orgId, eventNote: "rent_invoice_payments:service" });
}

  // Compute fee split in CODE (single source of truth)
  const split = computePlatformFeeSplit({
    paymentKind: "rent",
    amount: amountMajor,
    currency,
  });

  // Write computed amounts into payments row (DB ensure_payment_splits reads these)
  await client.query(
    `
    UPDATE public.payments
    SET
      platform_fee_amount = $2::numeric(15,2),
      payee_amount        = $3::numeric(15,2),
      currency            = COALESCE(currency, $4::text),
      updated_at          = NOW()
    WHERE id = $1::uuid
      AND deleted_at IS NULL;
    `,
    [payment.id, split.platformFee, split.payeeNet, currency]
  );

  // Ensure payment_splits exist (idempotent). If they already exist, this does nothing.
  await client.query(`SELECT public.ensure_payment_splits($1::uuid);`, [payment.id]);

  // Now update gateway info + mark successful (trigger will credit wallets)
  await client.query(
    `
    UPDATE public.payments
    SET
      status = 'successful'::public.payment_status,
      gateway_transaction_id = COALESCE($2, gateway_transaction_id),
      gateway_response = COALESCE($3::jsonb, gateway_response),
      completed_at = COALESCE(completed_at, NOW()),
      updated_at = NOW()
    WHERE id = $1::uuid
      AND deleted_at IS NULL;
    `,
    [payment.id, args.gatewayTransactionId ?? null, args.gatewayResponse ?? null]
  );

  // link invoice_payments (rent_invoices <-> payments)
  await client.query(
    `
    INSERT INTO public.invoice_payments (invoice_id, payment_id, amount)
    VALUES ($1::uuid, $2::uuid, $3::numeric)
    ON CONFLICT (invoice_id, payment_id) DO NOTHING;
    `,
    [payment.reference_id, payment.id, payment.amount]
  );

  // update invoice paid_amount and mark paid if fully paid
  const upd = await client.query<{ total_amount: string; paid_amount: string; status: string }>(
    `
    UPDATE public.rent_invoices ri
    SET
      paid_amount = COALESCE(ri.paid_amount, 0) + $2::numeric,
      status = CASE
        WHEN (COALESCE(ri.paid_amount, 0) + $2::numeric) >= ri.total_amount
          THEN 'paid'::public.invoice_status
        ELSE ri.status
      END,
      paid_at = CASE
        WHEN (COALESCE(ri.paid_amount, 0) + $2::numeric) >= ri.total_amount
          THEN COALESCE(ri.paid_at, NOW())
        ELSE ri.paid_at
      END,
      updated_at = NOW()
    WHERE ri.id = $1::uuid
      AND ri.deleted_at IS NULL
    RETURNING ri.total_amount::text, ri.paid_amount::text, ri.status::text;
    `,
    [payment.reference_id, payment.amount]
  );

  if (!upd.rows[0]) return { ok: true, reason: "INVOICE_NOT_FOUND_OR_DELETED" };
  return { ok: true };
}

/**
 * Paystack signature verification (HMAC SHA512)
 * Requires:
 *  - process.env.PAYSTACK_SECRET_KEY
 *  - raw request body (best with @fastify/raw-body)
 */
export function verifyPaystackSignature(opts: {
  rawBody: string | Buffer;
  signature: string | undefined;
  secret: string | undefined;
}): { ok: boolean; reason?: string } {
  const { rawBody, signature, secret } = opts;

  if (!secret) return { ok: false, reason: "PAYSTACK_SECRET_KEY_MISSING" };
  if (!signature) return { ok: false, reason: "PAYSTACK_SIGNATURE_HEADER_MISSING" };

  const mac = createHmac("sha512", secret).update(rawBody).digest("hex");

  // constant-time compare
  const a = Buffer.from(mac);
  const b = Buffer.from(signature);

  if (a.length !== b.length) return { ok: false, reason: "SIGNATURE_LENGTH_MISMATCH" };
  const match = timingSafeEqual(a, b);

  return match ? { ok: true } : { ok: false, reason: "SIGNATURE_MISMATCH" };
}