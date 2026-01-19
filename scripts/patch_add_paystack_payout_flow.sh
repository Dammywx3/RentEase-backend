#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(pwd)"
TS="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$REPO_ROOT/.patch_backups/$TS"
mkdir -p "$BACKUP_DIR"

echo "Repo: $REPO_ROOT"
echo "Backups: $BACKUP_DIR"

write_file () {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  if [[ -f "$path" ]]; then
    cp "$path" "$BACKUP_DIR/$(echo "$path" | sed 's#/#__#g')"
    echo "✅ Backup: $path"
  fi
  cat > "$path"
  echo "✅ Wrote: $path"
}

# -----------------------------
# 1) Paystack client
# -----------------------------
write_file "src/services/paystack_client.service.ts" <<'EOF'
type PaystackConfig = {
  secretKey: string;
};

type PaystackResponse<T> = {
  status: boolean;
  message?: string;
  data?: T;
};

function requirePaystackSecret(): string {
  const key = String(process.env.PAYSTACK_SECRET_KEY || "").trim();
  if (!key) throw new Error("PAYSTACK_SECRET_KEY is not set");
  return key;
}

async function paystackRequest<T>(cfg: PaystackConfig, path: string, opts: {
  method: "GET" | "POST";
  body?: any;
}): Promise<PaystackResponse<T>> {
  const url = `https://api.paystack.co${path}`;
  const res = await fetch(url, {
    method: opts.method,
    headers: {
      "Authorization": `Bearer ${cfg.secretKey}`,
      "Content-Type": "application/json",
    },
    body: opts.body ? JSON.stringify(opts.body) : undefined,
  });

  const text = await res.text();
  let json: any = null;
  try { json = text ? JSON.parse(text) : null; } catch { json = { status: false, message: text }; }

  if (!res.ok) {
    const msg = json?.message || `Paystack HTTP ${res.status}`;
    throw new Error(msg);
  }

  return json as PaystackResponse<T>;
}

export async function paystackCreateTransferRecipient(args: {
  name: string;
  accountNumber: string;
  bankCode: string;
  currency: string; // NGN
}): Promise<{ recipientCode: string; raw: any }> {
  const cfg = { secretKey: requirePaystackSecret() };

  const body = {
    type: "nuban",
    name: args.name,
    account_number: args.accountNumber,
    bank_code: args.bankCode,
    currency: args.currency,
  };

  const resp = await paystackRequest<{ recipient_code: string }>(cfg, "/transferrecipient", {
    method: "POST",
    body,
  });

  const code = String(resp?.data?.recipient_code || "").trim();
  if (!code) throw new Error("Paystack recipient_code missing");

  return { recipientCode: code, raw: resp };
}

export async function paystackInitiateTransfer(args: {
  amountMajor: number; // e.g. 1500.50
  currency: string;    // NGN
  recipientCode: string;
  reference: string;   // unique
  reason?: string | null;
}): Promise<{ transferCode: string | null; raw: any }> {
  const cfg = { secretKey: requirePaystackSecret() };

  // Paystack expects minor units (kobo) for NGN
  const amountMinor = Math.round(Number(args.amountMajor) * 100);
  if (!Number.isFinite(amountMinor) || amountMinor <= 0) throw new Error("Invalid payout amount");

  const body: any = {
    source: "balance",
    amount: amountMinor,
    recipient: args.recipientCode,
    reference: args.reference,
  };
  if (args.reason) body.reason = args.reason;

  const resp = await paystackRequest<any>(cfg, "/transfer", {
    method: "POST",
    body,
  });

  const transferCode = String(resp?.data?.transfer_code || "").trim() || null;
  return { transferCode, raw: resp };
}
EOF

# -----------------------------
# 2) Payouts service (DB)
# -----------------------------
write_file "src/services/payouts.service.ts" <<'EOF'
import type { PoolClient } from "pg";
import { assertRlsContext } from "../db/rls_guard.js";
import { setPgContext } from "../db/set_pg_context.js";
import { paystackCreateTransferRecipient, paystackInitiateTransfer } from "./paystack_client.service.js";

function asText(v: any): string { return String(v ?? "").trim(); }
function asNum(v: any): number { return Number(v); }

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

export async function createPaystackPayoutAccount(client: PoolClient, args: {
  organizationId: string;
  userId: string;
  currency: string; // NGN
  label?: string | null;

  name: string;
  accountNumber: string;
  bankCode: string;
  bankName?: string | null;
  makeDefault?: boolean;
}): Promise<{ payoutAccountId: string; recipientCode: string }> {
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
        and user_id = $2::uuid
        and deleted_at is null;
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

  // Keep raw in case you want to store it later (you currently don't have a column on payout_accounts)
  void raw;

  const payoutAccountId = asText(rows?.[0]?.id);
  if (!payoutAccountId) throw new Error("Failed to create payout account");

  return { payoutAccountId, recipientCode };
}

export async function requestPayout(client: PoolClient, args: {
  organizationId: string;
  userId: string;
  walletAccountId: string;
  payoutAccountId: string;
  amount: number;
  currency: string;
  note?: string | null;
}): Promise<{ payoutId: string }> {
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
      and deleted_at is null
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
      and deleted_at is null
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
  // We won't break your enum if it doesn't exist yet.
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
      [
        args.organizationId,
        args.walletAccountId,
        payoutId,
        amount,
        args.currency,
        args.note ?? "payout request",
      ]
    );
  }

  return { payoutId };
}

export async function processPayoutPaystack(client: PoolClient, args: {
  organizationId: string;
  payoutId: string;
  actorUserId?: string | null; // admin/service user id if you want to set it
}): Promise<{ ok: true }> {
  // service/admin context (RLS policies allow is_admin() or rentease_service)
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

  if (status === "successful") return { ok: true };
  if (status !== "pending" && status !== "failed") {
    // already processing etc.
    return { ok: true };
  }

  if (asText(r.provider) !== "paystack") throw new Error("Unsupported provider");

  const recipientCode = asText(r.provider_token);
  if (!recipientCode) throw new Error("Missing payout recipient_code");

  const amountMajor = Number(r.amount);
  if (!Number.isFinite(amountMajor) || amountMajor <= 0) throw new Error("Invalid payout amount");

  const reference = `payout_${args.payoutId}`;

  // Initiate transfer
  const { transferCode, raw } = await paystackInitiateTransfer({
    amountMajor,
    currency: asText(r.currency) || "NGN",
    recipientCode,
    reference,
    reason: "RentEase payout",
  });

  // Mark payout as processing with gateway info
  await client.query(
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
    [args.payoutId, args.organizationId, transferCode ?? reference, JSON.stringify(raw)]
  );

  return { ok: true };
}

export async function finalizePaystackTransferEvent(client: PoolClient, args: {
  organizationId: string;
  event: any;
}): Promise<{ ok: true } | { ok: false; error: string }> {
  await setPgContext(client, { organizationId: args.organizationId, userId: null, role: "admin" });
  await assertRlsContext(client);

  const evt = args.event || {};
  const evName = asText(evt.event);

  if (evName !== "transfer.success" && evName !== "transfer.failed" && evName !== "transfer.reversed") {
    return { ok: true };
  }

  const data = evt.data || {};
  const reference = asText(data.reference);
  const transferCode = asText(data.transfer_code);
  const gatewayId = transferCode || reference;

  if (!gatewayId) return { ok: false, error: "MISSING_GATEWAY_ID" };

  const newStatus =
    evName === "transfer.success"
      ? "successful"
      : evName === "transfer.reversed"
      ? "reversed"
      : "failed";

  // Update by gateway_payout_id OR our reference fallback
  await client.query(
    `
    update public.payouts
    set
      status = $3::public.payout_status,
      gateway_payout_id = coalesce(gateway_payout_id, $4::text),
      gateway_response = coalesce(gateway_response, '{}'::jsonb) || $5::jsonb,
      processed_at = coalesce(processed_at, now()),
      updated_at = now()
    where organization_id = $1::uuid
      and (
        gateway_payout_id = $4::text
        or gateway_payout_id = $6::text
        or ('payout_' || id::text) = $6::text
      );
    `,
    [
      args.organizationId,
      args.organizationId, // unused but keep args aligned
      newStatus,
      gatewayId,
      JSON.stringify(evt),
      reference,
    ]
  );

  return { ok: true };
}
EOF

# -----------------------------
# 3) Routes
# -----------------------------
write_file "src/routes/payouts.routes.ts" <<'EOF'
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
  fastify.get("/payouts", { preHandler: [fastify.authenticate] }, async (request, reply) => {
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

  fastify.post("/payouts/request", {
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
    "/payouts/:payoutId/process",
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
EOF

# -----------------------------
# 4) Register routes (best-effort)
# -----------------------------
echo "Registering payoutRoutes in your routes index (best effort)..."

TARGETS="$(rg -l "purchasesRoutes" src/routes 2>/dev/null || true)"
COUNT="$(echo "$TARGETS" | sed '/^\s*$/d' | wc -l | tr -d ' ')"

if [[ "$COUNT" == "1" ]]; then
  ROUTE_FILE="$(echo "$TARGETS" | head -n 1)"
  cp "$ROUTE_FILE" "$BACKUP_DIR/$(echo "$ROUTE_FILE" | sed 's#/#__#g')"
  echo "✅ Backup: $ROUTE_FILE"

  perl -0777 -i -pe '
    if ($_ !~ /payoutRoutes/) {
      s/(from\s+["'\'']\.\/purchases\.routes\.js["'\''];\s*)/$1import { payoutRoutes } from ".\/payouts.routes.js";\n/s;
      s/(fastify\.register\(\s*purchasesRoutes\s*,\s*\{\s*prefix:\s*["'\'']\/purchases["'\'']\s*\}\s*\);\s*)/$1\n  fastify.register(payoutRoutes);\n/s;
    }
  ' "$ROUTE_FILE"

  echo "✅ Patched route registration: $ROUTE_FILE"
else
  echo "[WARN] Could not uniquely find your route index file."
  echo "       Search results:"
  echo "$TARGETS"
  echo "       You must register payoutRoutes manually somewhere you register purchasesRoutes:"
  echo "         import { payoutRoutes } from \"./payouts.routes.js\";"
  echo "         fastify.register(payoutRoutes);"
fi

echo "DONE ✅"
EOF

Run:
```bash
