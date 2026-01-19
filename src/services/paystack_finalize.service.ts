// src/services/paystack_finalize.service.ts
import type { PoolClient } from "pg";
import { computePlatformFeeSplit } from "../config/fees.config.js";
import { setPgContext } from "../db/set_pg_context.js";
import { assertRlsContext } from "../db/rls_guard.js";

type PaystackEvent = {
  event?: string;
  data?: {
    reference?: string;
    id?: number | string;
    amount?: number; // usually minor units (kobo)
    currency?: string; // e.g. "NGN"
    status?: string;
  };
};

type PaymentRow = {
  id: string;

  // ✅ Derived via join (payments table does NOT have organization_id)
  organization_id: string;

  tenant_id: string | null;
  listing_id: string | null;
  property_id: string | null;

  amount: string;
  currency: string | null;
  status: string | null;

  reference_type: string | null;
  reference_id: string | null;
};

function asText(v: any): string {
  return String(v ?? "").trim();
}
function asNum(v: any): number {
  const n = Number(v);
  return Number.isFinite(n) ? n : NaN;
}

function approxEqual(a: number, b: number, eps = 0.01) {
  return Math.abs(a - b) <= eps;
}

async function ensureOrgContextMatchesPayment(client: PoolClient, paymentOrgId: string) {
  const { rows } = await client.query<{
    org_id: string | null;
    user_id: string | null;
    current_user: string | null;
    role: string | null;
    event_note: string | null;
  }>(
    `
    select
      nullif(current_setting('app.organization_id', true), '') as org_id,
      nullif(current_setting('app.user_id', true), '') as user_id,
      nullif(current_setting('app.current_user', true), '') as current_user,
      nullif(current_setting('app.role', true), '') as role,
      nullif(current_setting('app.event_note', true), '') as event_note
    `
  );

  const cur = rows?.[0];
  const existingOrg = (cur?.org_id ?? "").trim();
  if (existingOrg && existingOrg === paymentOrgId) return;

  const userId = (cur?.user_id ?? cur?.current_user ?? "").trim() || null;
  const role = (cur?.role ?? "").trim() || null;
  const eventNote = (cur?.event_note ?? "").trim() || null;

  await setPgContext(client, {
    userId,
    organizationId: paymentOrgId,
    role,
    eventNote: eventNote || "paystack:ensure_org",
  });
}

async function hasColumn(client: PoolClient, table: string, col: string): Promise<boolean> {
  const { rows } = await client.query(
    `
    select 1
    from pg_attribute
    where attrelid = $1::regclass
      and attname = $2
      and attisdropped = false
    limit 1;
    `,
    [table, col]
  );
  return !!rows?.[0];
}

/**
 * Ensure the payment->purchase link exists (idempotent).
 */
async function ensurePurchasePaymentLink(
  client: PoolClient,
  args: { organizationId: string; purchaseId: string; paymentId: string; amountMajor: number }
) {
  await client.query(
    `
    insert into public.property_purchase_payments (organization_id, purchase_id, payment_id, amount)
    values ($1::uuid, $2::uuid, $3::uuid, $4::numeric)
    on conflict (purchase_id, payment_id) do nothing;
    `,
    [args.organizationId, args.purchaseId, args.paymentId, args.amountMajor]
  );
}

/**
 * Recompute + update purchase aggregates from property_purchase_payments.
 * Safe to run multiple times (idempotent).
 */
async function reconcilePurchaseFromLinks(
  client: PoolClient,
  args: { organizationId: string; purchaseId: string; currency: string; note?: string | null }
): Promise<{ ok: true } | { ok: false; error: string; message?: string }> {
  // Lock purchase
  const hasDeposit = await hasColumn(client, "public.property_purchases", "deposit_amount");

  const q = hasDeposit
    ? `
      select
        agreed_price::text as agreed_price,
        deposit_amount::text as deposit_amount,
        escrow_held_amount::text as escrow_held_amount
      from public.property_purchases
      where id = $1::uuid
        and organization_id = $2::uuid
        and deleted_at is null
      limit 1
      for update;
    `
    : `
      select
        agreed_price::text as agreed_price,
        null::text as deposit_amount,
        escrow_held_amount::text as escrow_held_amount
      from public.property_purchases
      where id = $1::uuid
        and organization_id = $2::uuid
        and deleted_at is null
      limit 1
      for update;
    `;

  const { rows } = await client.query<{ agreed_price: string; deposit_amount: string | null; escrow_held_amount: string | null }>(
    q,
    [args.purchaseId, args.organizationId]
  );

  const pr = rows?.[0];
  if (!pr) return { ok: false, error: "PURCHASE_NOT_FOUND" };

  const agreed = asNum(pr.agreed_price);
  if (!Number.isFinite(agreed) || agreed <= 0) return { ok: false, error: "INVALID_PURCHASE_PRICE" };

  // total paid from links (only successful payments)
  const paidRes = await client.query<{ total_paid: string }>(
    `
    select coalesce(sum(ppp.amount),0)::text as total_paid
    from public.property_purchase_payments ppp
    join public.payments p on p.id = ppp.payment_id
    where ppp.purchase_id = $1::uuid
      and ppp.organization_id = $2::uuid
      and p.deleted_at is null
      and lower(p.status::text) = 'successful';
    `,
    [args.purchaseId, args.organizationId]
  );

  const totalPaid = asNum(paidRes.rows?.[0]?.total_paid ?? "0");
  const clampedPaid = Math.min(Math.max(totalPaid, 0), agreed);

  // determine payment_status
  let nextStatus: "unpaid" | "deposit_paid" | "partially_paid" | "paid" = "unpaid";
  if (clampedPaid <= 0) nextStatus = "unpaid";
  else if (clampedPaid >= agreed) nextStatus = "paid";
  else {
    const dep = asNum(pr.deposit_amount ?? "");
    if (Number.isFinite(dep) && dep > 0 && clampedPaid >= dep) nextStatus = "deposit_paid";
    else nextStatus = "partially_paid";
  }

  // latest successful payment id
  const lastPay = await client.query<{ payment_id: string | null }>(
    `
    select ppp.payment_id::text as payment_id
    from public.property_purchase_payments ppp
    join public.payments p on p.id = ppp.payment_id
    where ppp.purchase_id = $1::uuid
      and ppp.organization_id = $2::uuid
      and lower(p.status::text) = 'successful'
    order by ppp.created_at desc
    limit 1;
    `,
    [args.purchaseId, args.organizationId]
  );
  const lastPaymentId = asText(lastPay.rows?.[0]?.payment_id ?? "") || null;

  // Update purchase aggregates
  await client.query(
    `
    update public.property_purchases
    set
      paid_amount = $3::numeric,
      payment_status = $4::purchase_payment_status,
      last_payment_id = coalesce(last_payment_id, $5::uuid),
      paid_at = case when $4::text = 'paid' then coalesce(paid_at, now()) else paid_at end,
      updated_at = now()
    where id = $1::uuid
      and organization_id = $2::uuid
      and deleted_at is null;
    `,
    [args.purchaseId, args.organizationId, clampedPaid, nextStatus, lastPaymentId]
  );

  // Set escrow hold to NEW TOTAL (idempotent + avoids "double add" overfund)
  // Only if > 0
  if (clampedPaid > 0) {
    await client.query(
      `select public.purchase_escrow_hold($1::uuid, $2::uuid, $3::numeric, $4::text, $5::text);`,
      [args.purchaseId, args.organizationId, clampedPaid, args.currency, args.note ?? "paystack purchase escrow reconcile"]
    );
  }

  return { ok: true };
}

export async function finalizePaystackChargeSuccess(
  client: PoolClient,
  evt: PaystackEvent
): Promise<{ ok: true } | { ok: false; error: string; message?: string }> {
  if ((evt.event ?? "") !== "charge.success") return { ok: true };

  const reference = asText(evt.data?.reference);
  if (!reference) return { ok: false, error: "MISSING_REFERENCE" };

  // ✅ payments has NO organization_id, so derive it via listing/property
  const payRes = await client.query<PaymentRow>(
    `
    select
      p.id::text as id,
      coalesce(pl.organization_id, pr.organization_id)::text as organization_id,

      p.tenant_id::text,
      p.listing_id::text,
      p.property_id::text,

      p.amount::text,
      p.currency,
      p.status::text,
      p.reference_type::text,
      p.reference_id::text
    from public.payments p
    left join public.property_listings pl
      on pl.id = p.listing_id
     and pl.deleted_at is null
    left join public.properties pr
      on pr.id = p.property_id
     and pr.deleted_at is null
    where p.transaction_reference = $1
      and p.deleted_at is null
    limit 1;
    `,
    [reference]
  );

  const payment = payRes.rows[0];
  if (!payment) {
    return { ok: false, error: "PAYMENT_NOT_FOUND", message: `reference=${reference}` };
  }
  if (!payment.organization_id) {
    return { ok: false, error: "ORG_NOT_RESOLVED", message: `paymentId=${payment.id}` };
  }

  // Make sure RLS org matches the derived org
  await ensureOrgContextMatchesPayment(client, payment.organization_id);
  await assertRlsContext(client);

  const amountMajor = asNum(payment.amount);
  if (!Number.isFinite(amountMajor) || amountMajor <= 0) {
    return { ok: false, error: "INVALID_PAYMENT_AMOUNT", message: `payments.amount=${payment.amount}` };
  }

  const currency = asText(payment.currency || evt.data?.currency || "USD") || "USD";

  // Validate paystack amount if present
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

  const orgId = payment.organization_id;
  const isSuccessful = asText(payment.status).toLowerCase() === "successful";
  const refType = asText(payment.reference_type);

  // ------------------------------------------------------------
  // ✅ PURCHASE: ALWAYS reconcile purchase aggregates (even if payment already successful)
  // ------------------------------------------------------------
  if (refType === "purchase" && asText(payment.reference_id)) {
    const purchaseId = asText(payment.reference_id);
    if (!purchaseId) return { ok: false, error: "MISSING_PURCHASE_ID" };

    // Mark payment successful idempotently (only sets completed_at if missing)
    await client.query(
      `
      update public.payments
      set
        status = 'successful'::public.payment_status,
        completed_at = coalesce(completed_at, now()),
        gateway_transaction_id = coalesce(gateway_transaction_id, $2::text),
        gateway_response = coalesce(gateway_response, $3::jsonb),
        currency = coalesce(currency, $4::text),
        updated_at = now()
      where id = $1::uuid
        and deleted_at is null;
      `,
      [payment.id, asText(evt.data?.id ?? ""), JSON.stringify(evt), currency]
    );

    // Ensure link row exists (idempotent)
    await ensurePurchasePaymentLink(client, {
      organizationId: orgId,
      purchaseId,
      paymentId: payment.id,
      amountMajor,
    });

    // Reconcile purchase aggregates + escrow hold to NEW TOTAL
    const rec = await reconcilePurchaseFromLinks(client, {
      organizationId: orgId,
      purchaseId,
      currency,
      note: `paystack:charge.success:${reference}`,
    });

    if (!rec.ok) return rec;
    return { ok: true };
  }

  // For non-purchase, if payment already successful we can safely stop here
  if (isSuccessful) return { ok: true };

  // ------------------------------------------------------------
  // NON-PURCHASE: resolve payee
  // ------------------------------------------------------------
  let payeeUserId: string | null = null;

  if (refType === "rent_invoice" && asText(payment.reference_id)) {
    const r = await client.query<{ payee_user_id: string | null }>(
      `
      select
        p.owner_id::text as payee_user_id
      from public.rent_invoices ri
      join public.properties p on p.id = ri.property_id
      where ri.id = $1::uuid
        and ri.organization_id = $2::uuid
        and ri.deleted_at is null
      limit 1;
      `,
      [payment.reference_id, orgId]
    );
    payeeUserId = r.rows[0]?.payee_user_id ?? null;
  } else {
    return {
      ok: false,
      error: "UNSUPPORTED_REFERENCE_TYPE",
      message: `reference_type=${payment.reference_type}`,
    };
  }

  if (!payeeUserId) return { ok: false, error: "PAYEE_RESOLVE_FAILED" };

  // Compute split
  const split = computePlatformFeeSplit({
    paymentKind: "rent",
    amount: amountMajor,
    currency,
  });

  if (!Number.isFinite(split.platformFee) || !Number.isFinite(split.payeeNet)) {
    return { ok: false, error: "SPLIT_CALC_FAILED" };
  }

  // Insert splits idempotently
  await client.query(
    `
    insert into public.payment_splits (
      payment_id, split_type, beneficiary_kind, beneficiary_user_id, amount, currency
    )
    select
      $1::uuid,
      'platform_fee'::public.split_type,
      'platform'::public.beneficiary_kind,
      null,
      $2::numeric,
      $3::text
    where not exists (
      select 1
      from public.payment_splits
      where payment_id = $1::uuid
        and split_type = 'platform_fee'::public.split_type
    );
    `,
    [payment.id, split.platformFee, currency]
  );

  await client.query(
    `
    insert into public.payment_splits (
      payment_id, split_type, beneficiary_kind, beneficiary_user_id, amount, currency
    )
    select
      $1::uuid,
      'payee'::public.split_type,
      'user'::public.beneficiary_kind,
      $2::uuid,
      $3::numeric,
      $4::text
    where not exists (
      select 1
      from public.payment_splits
      where payment_id = $1::uuid
        and split_type = 'payee'::public.split_type
    );
    `,
    [payment.id, payeeUserId, split.payeeNet, currency]
  );

  // Optional: rent invoice linking + mark paid
  if (refType === "rent_invoice" && asText(payment.reference_id)) {
    await client.query(
      `
      insert into public.invoice_payments (invoice_id, payment_id, amount)
      values ($1::uuid, $2::uuid, $3::numeric)
      on conflict do nothing;
      `,
      [payment.reference_id, payment.id, amountMajor]
    );

    await client.query(
      `
      update public.rent_invoices ri
      set
        paid_amount = coalesce(ri.paid_amount, 0) + $1::numeric,
        paid_at = now(),
        status = case
          when (coalesce(ri.paid_amount, 0) + $1::numeric) >= ri.total_amount
            then 'paid'::public.invoice_status
          else ri.status
        end,
        updated_at = now()
      where ri.id = $2::uuid
        and ri.organization_id = $3::uuid
        and ri.deleted_at is null;
      `,
      [amountMajor, payment.reference_id, orgId]
    );
  }

  // Update payment to successful AFTER splits exist
  await client.query(
    `
    update public.payments
    set
      status = 'successful'::public.payment_status,
      completed_at = now(),
      gateway_transaction_id = coalesce(gateway_transaction_id, $2::text),
      gateway_response = coalesce(gateway_response, $3::jsonb),
      platform_fee_amount = $4::numeric,
      payee_amount = $5::numeric,
      currency = coalesce(currency, $6::text),
      updated_at = now()
    where id = $1::uuid
      and deleted_at is null;
    `,
    [
      payment.id,
      asText(evt.data?.id ?? ""),
      JSON.stringify(evt),
      split.platformFee,
      split.payeeNet,
      currency,
    ]
  );

  return { ok: true };
}
