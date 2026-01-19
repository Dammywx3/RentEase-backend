// src/services/payouts.service.ts
import type { PoolClient } from "pg";
import { assertRlsContext } from "../db/rls_guard.js";
import { setPgContext } from "../db/set_pg_context.js";
import { paystackCreateTransferRecipient, paystackInitiateTransfer } from "./paystack_client.service.js";

function asText(v: any): string {
  return String(v ?? "").trim();
}
function asNum(v: any): number {
  const n = Number(v);
  return Number.isFinite(n) ? n : NaN;
}

async function hasWalletTxnType(client: PoolClient, enumLabel: string): Promise<boolean> {
  const { rows } = await client.query<{ ok: boolean }>(
    `
    select exists(
      select 1
      from pg_type t
      join pg_enum e on e.enumtypid = t.oid
      where t.typname = 'wallet_transaction_type'
        and e.enumlabel = $1
    ) as ok;
    `,
    [enumLabel]
  );
  return Boolean(rows?.[0]?.ok);
}

export async function createPaystackPayoutAccount(
  client: PoolClient,
  args: {
    organizationId: string;
    userId: string;
    currency: string; // NGN
    label?: string | null;

    name: string;
    accountNumber: string;
    bankCode: string;
    bankName?: string | null;
    makeDefault?: boolean;
  }
): Promise<{ payoutAccountId: string; recipientCode: string }> {
  await setPgContext(client, { organizationId: args.organizationId, userId: args.userId, role: null });
  await assertRlsContext(client);

  const { recipientCode, raw } = await paystackCreateTransferRecipient({
    name: args.name,
    accountNumber: args.accountNumber,
    bankCode: args.bankCode,
    currency: args.currency,
  });

  const last4 = args.accountNumber.slice(-4);

  // if makeDefault, unset existing defaults
  if (args.makeDefault) {
    await client.query(
      `
      update public.payout_accounts
      set is_default = false, updated_at = now()
      where organization_id = $1::uuid
        and user_id = $2::uuid;
      `,
      [args.organizationId, args.userId]
    );
  }

  const { rows } = await client.query<{ id: string }>(
    `
    insert into public.payout_accounts (
      organization_id, user_id, currency,
      provider, provider_token,
      label, account_name, bank_name, last4,
      is_default
    )
    values (
      $1::uuid, $2::uuid, $3::text,
      'paystack', $4::text,
      $5::text, $6::text, $7::text, $8::varchar(4),
      $9::boolean
    )
    on conflict (user_id, provider, provider_token)
    do update set
      currency = excluded.currency,
      label = excluded.label,
      account_name = excluded.account_name,
      bank_name = excluded.bank_name,
      last4 = excluded.last4,
      is_default = excluded.is_default,
      updated_at = now()
    returning id::text as id;
    `,
    [
      args.organizationId,
      args.userId,
      args.currency,
      recipientCode,
      args.label ?? null,
      args.name,
      args.bankName ?? null,
      last4,
      Boolean(args.makeDefault),
    ]
  );

  void raw;

  const payoutAccountId = asText(rows?.[0]?.id);
  if (!payoutAccountId) throw new Error("Failed to create payout account");

  return { payoutAccountId, recipientCode };
}

export async function requestPayout(
  client: PoolClient,
  args: {
    organizationId: string;
    userId: string;
    walletAccountId: string;
    payoutAccountId: string;
    amount: number;
    currency: string;
    note?: string | null;
  }
): Promise<{ payoutId: string }> {
  await setPgContext(client, { organizationId: args.organizationId, userId: args.userId, role: null });
  await assertRlsContext(client);

  const amount = asNum(args.amount);
  if (!Number.isFinite(amount) || amount <= 0) throw new Error("Invalid payout amount");

  // Ensure payout account belongs to this user/org (RLS also enforces)
  const pa = await client.query(
    `
    select id::text, provider, provider_token, currency
    from public.payout_accounts
    where id = $1::uuid
      and organization_id = $2::uuid
      and user_id = $3::uuid
    limit 1;
    `,
    [args.payoutAccountId, args.organizationId, args.userId]
  );
  if (!pa.rows?.[0]) throw new Error("Payout account not found");

  // Ensure wallet belongs to user/org and currency matches
  const wa = await client.query(
    `
    select id::text, currency
    from public.wallet_accounts
    where id = $1::uuid
      and organization_id = $2::uuid
      and user_id = $3::uuid
    limit 1;
    `,
    [args.walletAccountId, args.organizationId, args.userId]
  );
  const waRow = wa.rows?.[0];
  if (!waRow) throw new Error("Wallet not found");

  const cur = asText(waRow.currency || args.currency);
  if (cur && args.currency && cur !== args.currency) throw new Error("Currency mismatch");

  const { rows } = await client.query<{ id: string }>(
    `
    insert into public.payouts (
      organization_id, user_id,
      wallet_account_id, payout_account_id,
      amount, currency, status,
      gateway_payout_id, gateway_response,
      requested_at, processed_at
    )
    values (
      $1::uuid, $2::uuid,
      $3::uuid, $4::uuid,
      $5::numeric, $6::text, 'pending'::public.payout_status,
      null, null,
      now(), null
    )
    returning id::text as id;
    `,
    [
      args.organizationId,
      args.userId,
      args.walletAccountId,
      args.payoutAccountId,
      amount,
      args.currency,
    ]
  );

  const payoutId = asText(rows?.[0]?.id);
  if (!payoutId) throw new Error("Failed to create payout");

  // Optional: reserve/debit funds if you have a txn_type for it.
  if (await hasWalletTxnType(client, "debit_payout")) {
    await client.query(
      `
      insert into public.wallet_transactions(
        organization_id, wallet_account_id, txn_type,
        reference_type, reference_id, amount, currency, note
      )
      values (
        $1::uuid, $2::uuid, 'debit_payout'::public.wallet_transaction_type,
        'payout', $3::uuid, $4::numeric, $5::text, $6::text
      )
      on conflict do nothing;
      `,
      [args.organizationId, args.walletAccountId, payoutId, amount, args.currency, args.note ?? "payout request"]
    );
  }

  return { payoutId };
}

export async function processPayoutPaystack(
  client: PoolClient,
  args: {
    organizationId: string;
    payoutId: string;
    actorUserId?: string | null; // MUST be a real admin user UUID for is_admin() to pass
  }
): Promise<{ ok: true }> {
  await setPgContext(client, {
    organizationId: args.organizationId,
    userId: args.actorUserId ?? null,
    role: "admin",
    eventNote: `process payout ${args.payoutId}`,
  });
  await assertRlsContext(client);

  const { rows } = await client.query<any>(
    `
    select
      p.id::text,
      p.user_id::text,
      p.amount::text,
      p.currency,
      p.status::text,
      p.gateway_payout_id::text as gateway_payout_id,
      pa.provider,
      pa.provider_token
    from public.payouts p
    join public.payout_accounts pa on pa.id = p.payout_account_id
    where p.id = $1::uuid
      and p.organization_id = $2::uuid
    limit 1
    for update;
    `,
    [args.payoutId, args.organizationId]
  );

  const r = rows?.[0];
  if (!r) throw new Error("Payout not found");

  const status = asText(r.status).toLowerCase();
  const existingGatewayId = asText(r.gateway_payout_id);

  // ✅ Idempotency / safety:
  if (status === "successful") return { ok: true };
  if (existingGatewayId) return { ok: true }; // already initiated before
  if (status !== "pending" && status !== "failed") return { ok: true }; // processing/reversed/etc.

  if (asText(r.provider) !== "paystack") throw new Error("Unsupported provider");

  const recipientCode = asText(r.provider_token);
  if (!recipientCode) throw new Error("Missing payout recipient_code");

  const amountMajor = asNum(r.amount);
  if (!Number.isFinite(amountMajor) || amountMajor <= 0) throw new Error("Invalid payout amount");

  const reference = `payout_${args.payoutId}`;

  const { transferCode, raw } = await paystackInitiateTransfer({
    amountMajor,
    currency: asText(r.currency) || "NGN",
    recipientCode,
    reference,
    reason: "RentEase payout",
  });

  const gatewayId = asText(transferCode) || reference;

  
const upd = await client.query(
    `
    update public.payouts
    set
      status = 'processing'::public.payout_status,
      gateway_payout_id = coalesce(gateway_payout_id, $3::text),
      gateway_response = coalesce(gateway_response, '{}'::jsonb) || $4::jsonb,
      processed_at = now(),
      updated_at = now()
    where id = $1::uuid
      and organization_id = $2::uuid;
    `,
    [args.payoutId, args.organizationId, gatewayId, JSON.stringify(raw ?? {})]
  );

  return { ok: true };
}



export async function finalizePaystackTransferEvent(
  client: PoolClient,
  args: {
    event: any;
    actorUserId?: string | null;
    organizationId?: string | null; // optional; we will derive from payout row if missing
  }
): Promise<{ ok: true } | { ok: false; error: string; message?: string }> {
  const asText = (v: any) => (v == null ? "" : String(v)).trim();

  const evName = asText(args?.event?.event);
  if (evName !== "transfer.success" && evName !== "transfer.failed" && evName !== "transfer.reversed") {
    return { ok: true };
  }

  const ref = asText(args?.event?.data?.reference);
  const transferCode = asText(args?.event?.data?.transfer_code);
  const paystackId = asText(args?.event?.data?.id);

  // Prefer transfer_code, else reference, else id
  const gatewayKey = transferCode || ref || paystackId;

  // If reference is "payout_<uuid>", extract payoutId
  let payoutIdFromRef: string | null = null;
  if (ref.toLowerCase().startsWith("payout_")) {
    const maybe = ref.slice("payout_".length).trim();
    // basic uuid format check (avoid throwing)
    if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(maybe)) {
      payoutIdFromRef = maybe;
    }
  }

  // Find payout by:
  // 1) gateway_payout_id == transfer_code
  // 2) gateway_payout_id == reference
  // 3) id == extracted uuid from reference payout_<uuid>
  const found = await client.query<{
    id: string;
    organization_id: string;
    status: string | null;
  }>(
    `
    select
      p.id::text as id,
      p.organization_id::text as organization_id,
      p.status::text as status
    from public.payouts p
    where
      
(p.gateway_payout_id = nullif($1,''))
      or (p.gateway_payout_id = nullif($2,''))
      or (p.id = nullif($3::text,'')::uuid)
    limit 1
    for update;
    `,
    [transferCode, ref, payoutIdFromRef]
  );

  const payout = found.rows[0];
  if (!payout) {
    return {
      ok: false,
      error: "PAYOUT_NOT_FOUND",
      message: `transfer_code=${transferCode || "-"} reference=${ref || "-"} payoutIdFromRef=${payoutIdFromRef || "-"}`,
    };
  }

  // Must be a real admin user UUID for is_admin() to pass (or rentease_service)
  const actor = asText(args.actorUserId || process.env.WEBHOOK_ACTOR_USER_ID || "");
  if (!actor) return { ok: false, error: "WEBHOOK_ACTOR_USER_ID_MISSING" };

  // Ensure admin context + correct org before UPDATE (RLS + triggers)
  await setPgContext(client, {
    organizationId: payout.organization_id,
    userId: actor,
    role: "admin",
    eventNote: `paystack:${evName}`,
  });

  const nextStatus =
    evName === "transfer.success"
      ? "paid"
      : evName === "transfer.reversed"
      ? "reversed"
      : "failed";

  await client.query(
    `
    update public.payouts
    set
      status = $2::public.payout_status,
      processed_at = coalesce(processed_at, now()),
      gateway_payout_id = coalesce(gateway_payout_id, $3::text),
      gateway_response = coalesce(gateway_response, '{}'::jsonb) || $4::jsonb,
      updated_at = now()
    where id = $1::uuid;
    `,
    [payout.id, nextStatus, gatewayKey || null, JSON.stringify(args.event)]
  );  return { ok: true };
}
  
  