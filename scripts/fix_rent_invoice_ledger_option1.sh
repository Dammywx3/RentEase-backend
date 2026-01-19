#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== Fix rent invoice ledger flow (Option 1: rent_payments + wallet ledger) =="

mkdir -p scripts/.bak
ts="$(date +%Y%m%d_%H%M%S)"

# --- backups ---
for f in \
  src/services/rent_invoices.service.ts \
  src/routes/rent_invoices.ts \
; do
  if [ -f "$f" ]; then
    cp "$f" "scripts/.bak/$(basename "$f").bak.$ts"
    echo "✅ backup -> scripts/.bak/$(basename "$f").bak.$ts"
  fi
done

# --- 1) DB patch (new tables + wallet tx idempotency for rent_invoice) ---
cat > scripts/patch_rent_invoice_ledger_option1.sql <<'SQL'
-- Option 1: add dedicated rent payment tables that do NOT use public.payments
-- so we avoid the payments.amount == listing.listed_price trigger.

BEGIN;

-- 1) rent_payments (one per rent invoice pay)
CREATE TABLE IF NOT EXISTS public.rent_payments (
  id              uuid PRIMARY KEY DEFAULT rentease_uuid(),
  organization_id uuid NOT NULL DEFAULT current_organization_uuid() REFERENCES public.organizations(id),

  invoice_id   uuid NOT NULL REFERENCES public.rent_invoices(id) ON DELETE CASCADE,
  tenancy_id   uuid NOT NULL REFERENCES public.tenancies(id) ON DELETE RESTRICT,
  tenant_id    uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  property_id  uuid NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,

  amount        numeric(15,2) NOT NULL CHECK (amount > 0),
  currency      varchar(3) DEFAULT 'USD',
  payment_method text NOT NULL,
  status        text NOT NULL DEFAULT 'successful',

  created_at    timestamptz NOT NULL DEFAULT now()
);

-- Ensure one rent_payment per invoice (idempotent safety)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname='public'
      AND indexname='uniq_rent_payments_invoice'
  ) THEN
    CREATE UNIQUE INDEX uniq_rent_payments_invoice
      ON public.rent_payments(invoice_id);
  END IF;
END$$;

ALTER TABLE public.rent_payments ENABLE ROW LEVEL SECURITY;

-- Allow admin/service to write; allow invoice viewers to read
DO $$
BEGIN
  -- SELECT policy
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='rent_payments' AND policyname='rent_payments_select'
  ) THEN
    EXECUTE $p$
      CREATE POLICY rent_payments_select ON public.rent_payments
      FOR SELECT
      USING (
        organization_id = current_organization_uuid()
        AND EXISTS (
          SELECT 1
          FROM public.rent_invoices ri
          WHERE ri.id = rent_payments.invoice_id
            AND ri.deleted_at IS NULL
            AND ri.organization_id = current_organization_uuid()
            AND (is_admin() OR ri.tenant_id = current_user_uuid() OR is_property_owner_or_default_agent(ri.property_id))
        )
      );
    $p$;
  END IF;

  -- INSERT/UPDATE/DELETE policy
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='rent_payments' AND policyname='rent_payments_write_admin_or_service'
  ) THEN
    EXECUTE $p$
      CREATE POLICY rent_payments_write_admin_or_service ON public.rent_payments
      FOR ALL
      USING (is_admin() OR CURRENT_USER = 'rentease_service')
      WITH CHECK (organization_id = current_organization_uuid() AND (is_admin() OR CURRENT_USER = 'rentease_service'));
    $p$;
  END IF;
END$$;

-- 2) rent_invoice_payments (parallel to invoice_payments but points to rent_payments)
CREATE TABLE IF NOT EXISTS public.rent_invoice_payments (
  id              uuid PRIMARY KEY DEFAULT rentease_uuid(),
  organization_id uuid DEFAULT current_organization_uuid() REFERENCES public.organizations(id),

  invoice_id       uuid NOT NULL REFERENCES public.rent_invoices(id) ON DELETE CASCADE,
  rent_payment_id  uuid NOT NULL REFERENCES public.rent_payments(id) ON DELETE RESTRICT,

  amount           numeric(15,2) NOT NULL CHECK (amount > 0),
  created_at       timestamptz NOT NULL DEFAULT now()
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname='public'
      AND indexname='uniq_rent_invoice_payments_invoice'
  ) THEN
    CREATE UNIQUE INDEX uniq_rent_invoice_payments_invoice
      ON public.rent_invoice_payments(invoice_id);
  END IF;
END$$;

ALTER TABLE public.rent_invoice_payments ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='rent_invoice_payments' AND policyname='rent_invoice_payments_select'
  ) THEN
    EXECUTE $p$
      CREATE POLICY rent_invoice_payments_select ON public.rent_invoice_payments
      FOR SELECT
      USING (
        organization_id = current_organization_uuid()
        AND EXISTS (
          SELECT 1
          FROM public.rent_invoices ri
          WHERE ri.id = rent_invoice_payments.invoice_id
            AND ri.deleted_at IS NULL
            AND ri.organization_id = current_organization_uuid()
            AND (is_admin() OR ri.tenant_id = current_user_uuid() OR is_property_owner_or_default_agent(ri.property_id))
        )
      );
    $p$;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='rent_invoice_payments' AND policyname='rent_invoice_payments_write_admin_or_service'
  ) THEN
    EXECUTE $p$
      CREATE POLICY rent_invoice_payments_write_admin_or_service ON public.rent_invoice_payments
      FOR ALL
      USING (is_admin() OR CURRENT_USER = 'rentease_service')
      WITH CHECK (organization_id = current_organization_uuid() AND (is_admin() OR CURRENT_USER = 'rentease_service'));
    $p$;
  END IF;
END$$;

-- 3) wallet_transactions idempotency for rent_invoice credits
-- Your current unique index only covers reference_type='payment'. We add another for rent_invoice.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='public'
      AND indexname='uniq_wallet_tx_rent_invoice_credit'
  ) THEN
    CREATE UNIQUE INDEX uniq_wallet_tx_rent_invoice_credit
      ON public.wallet_transactions(wallet_account_id, reference_type, reference_id, txn_type)
      WHERE reference_type = 'rent_invoice';
  END IF;
END$$;

COMMIT;
SQL

echo "== Applying DB patch =="
psql -d "${DB_NAME:-rentease}" -f scripts/patch_rent_invoice_ledger_option1.sql
echo "✅ DB patch applied"

# --- 2) Patch service (adds rent_payments + wallet ledger on PAY) ---
cat > src/services/rent_invoices.service.ts <<'TS'
import type { PoolClient } from "pg";
import type { InvoiceStatus } from "../schemas/rent_invoices.schema.js";
import {
  findRentInvoiceByTenancyPeriod,
  insertRentInvoice,
  listRentInvoices,
} from "../repos/rent_invoices.repo.js";

type TenancyMini = {
  id: string;
  tenant_id: string;
  property_id: string;
  rent_amount: string;
};

export type RentInvoiceRow = {
  id: string;
  organization_id: string;
  tenancy_id: string;
  tenant_id: string;
  property_id: string;
  invoice_number: string | number | null;
  status: InvoiceStatus;
  period_start: string;
  period_end: string;
  due_date: string;
  subtotal: string;
  late_fee_amount: string | null;
  total_amount: string;
  currency: string | null;
  paid_amount: string | null;
  paid_at: string | null;
  notes: string | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
};

const RENT_INVOICE_SELECT = `
  id,
  organization_id,
  tenancy_id,
  tenant_id,
  property_id,
  invoice_number,
  status,
  period_start::text AS period_start,
  period_end::text AS period_end,
  due_date::text AS due_date,
  subtotal::text AS subtotal,
  late_fee_amount::text AS late_fee_amount,
  total_amount::text AS total_amount,
  currency,
  paid_amount::text AS paid_amount,
  paid_at::text AS paid_at,
  notes,
  created_at::text AS created_at,
  updated_at::text AS updated_at,
  deleted_at::text AS deleted_at
`;

// ------------------------------------
// LIST
// ------------------------------------
export async function getRentInvoices(
  client: PoolClient,
  args: {
    limit: number;
    offset: number;
    tenancyId?: string;
    tenantId?: string;
    propertyId?: string;
    status?: InvoiceStatus;
  }
) {
  return listRentInvoices(client, {
    limit: args.limit,
    offset: args.offset,
    tenancy_id: args.tenancyId,
    tenant_id: args.tenantId,
    property_id: args.propertyId,
    status: args.status,
  });
}

// ------------------------------------
// GENERATE (idempotent per tenancy+period)
// ------------------------------------
export async function generateRentInvoiceForTenancy(
  client: PoolClient,
  args: {
    tenancyId: string;
    periodStart: string;
    periodEnd: string;
    dueDate: string;

    subtotal?: number;
    lateFeeAmount?: number | null;
    currency?: string | null;
    status?: InvoiceStatus | null;
    notes?: string | null;
  }
): Promise<{ row: any; reused: boolean }> {
  const existing = await findRentInvoiceByTenancyPeriod(client, {
    tenancy_id: args.tenancyId,
    period_start: args.periodStart,
    period_end: args.periodEnd,
    due_date: args.dueDate,
  });
  if (existing) return { row: existing, reused: true };

  const { rows } = await client.query<TenancyMini>(
    `
    SELECT
      id,
      tenant_id,
      property_id,
      rent_amount::text AS rent_amount
    FROM public.tenancies
    WHERE id = $1::uuid
      AND deleted_at IS NULL
    LIMIT 1;
    `,
    [args.tenancyId]
  );

  const tenancy = rows[0];
  if (!tenancy) {
    const e: any = new Error("Tenancy not found");
    e.code = "TENANCY_NOT_FOUND";
    throw e;
  }

  const subtotal = typeof args.subtotal === "number" ? args.subtotal : Number(tenancy.rent_amount);
  const lateFee = args.lateFeeAmount == null ? 0 : Number(args.lateFeeAmount);
  const total = subtotal + lateFee;

  const currency = (args.currency ?? "USD") || "USD";
  const status: InvoiceStatus = (args.status ?? "issued") || "issued";

  const row = await insertRentInvoice(client, {
    tenancy_id: args.tenancyId,
    tenant_id: tenancy.tenant_id,
    property_id: tenancy.property_id,

    period_start: args.periodStart,
    period_end: args.periodEnd,
    due_date: args.dueDate,

    subtotal,
    late_fee_amount: lateFee,
    total_amount: total,

    currency,
    status,
    notes: args.notes ?? null,
  });

  return { row, reused: false };
}

// ------------------------------------
// PAY + LEDGER (Option 1)
// - mark invoice paid
// - create rent_payments + rent_invoice_payments
// - credit platform wallet in wallet_transactions
// ------------------------------------
async function ensurePlatformWallet(
  client: PoolClient,
  currency: string
): Promise<string> {
  const res = await client.query<{ id: string }>(
    `
    SELECT id
    FROM public.wallet_accounts
    WHERE organization_id = current_organization_uuid()
      AND is_platform_wallet = true
      AND currency = $1
    LIMIT 1;
    `,
    [currency]
  );

  const existing = res.rows[0]?.id;
  if (existing) return existing;

  // admin/service policy allows this
  const ins = await client.query<{ id: string }>(
    `
    INSERT INTO public.wallet_accounts (organization_id, user_id, currency, is_platform_wallet)
    VALUES (current_organization_uuid(), NULL, $1, true)
    RETURNING id;
    `,
    [currency]
  );

  return ins.rows[0]!.id;
}

async function recordRentPaymentAndLedger(
  client: PoolClient,
  invoice: RentInvoiceRow,
  paymentMethod: string,
  amount: number
) {
  const currency = (invoice.currency ?? "USD") || "USD";

  // 1) rent_payments (idempotent by uniq_rent_payments_invoice)
  const rp = await client.query<{ id: string }>(
    `
    INSERT INTO public.rent_payments (
      organization_id, invoice_id, tenancy_id, tenant_id, property_id,
      amount, currency, payment_method, status
    )
    VALUES (
      current_organization_uuid(), $1::uuid, $2::uuid, $3::uuid, $4::uuid,
      $5::numeric, $6, $7, 'successful'
    )
    ON CONFLICT (invoice_id) DO UPDATE
      SET amount = EXCLUDED.amount
    RETURNING id;
    `,
    [
      invoice.id,
      invoice.tenancy_id,
      invoice.tenant_id,
      invoice.property_id,
      amount,
      currency,
      paymentMethod,
    ]
  );
  const rentPaymentId = rp.rows[0]!.id;

  // 2) rent_invoice_payments (idempotent by uniq_rent_invoice_payments_invoice)
  await client.query(
    `
    INSERT INTO public.rent_invoice_payments (
      organization_id, invoice_id, rent_payment_id, amount
    )
    VALUES (
      current_organization_uuid(), $1::uuid, $2::uuid, $3::numeric
    )
    ON CONFLICT (invoice_id) DO NOTHING;
    `,
    [invoice.id, rentPaymentId, amount]
  );

  // 3) credit platform wallet (idempotent by uniq_wallet_tx_rent_invoice_credit)
  const platformWalletId = await ensurePlatformWallet(client, currency);

  await client.query(
    `
    INSERT INTO public.wallet_transactions (
      organization_id, wallet_account_id, txn_type,
      reference_type, reference_id,
      amount, currency, note
    )
    VALUES (
      current_organization_uuid(), $1::uuid, 'credit'::wallet_transaction_type,
      'rent_invoice', $2::uuid,
      $3::numeric, $4, $5
    )
    ON CONFLICT (wallet_account_id, reference_type, reference_id, txn_type)
      WHERE reference_type = 'rent_invoice'
    DO NOTHING;
    `,
    [
      platformWalletId,
      invoice.id,
      amount,
      currency,
      `Rent invoice ${invoice.invoice_number ?? invoice.id}`,
    ]
  );
}

export async function payRentInvoice(
  client: PoolClient,
  args: {
    invoiceId: string;
    paymentMethod: string;
    amount?: number | null;
  }
): Promise<{ row: RentInvoiceRow; alreadyPaid: boolean }> {
  const invRes = await client.query<RentInvoiceRow>(
    `
    SELECT ${RENT_INVOICE_SELECT}
    FROM public.rent_invoices
    WHERE id = $1::uuid
      AND deleted_at IS NULL
    LIMIT 1;
    `,
    [args.invoiceId]
  );

  const invoice = invRes.rows[0];
  if (!invoice) {
    const e: any = new Error("Invoice not found");
    e.code = "INVOICE_NOT_FOUND";
    throw e;
  }

  // idempotent
  if (invoice.status === "paid") {
    return { row: invoice, alreadyPaid: true };
  }

  const total = Number(invoice.total_amount);
  const amount = typeof args.amount === "number" ? args.amount : total;

  if (Number(amount) !== Number(total)) {
    const e: any = new Error(
      `Payment.amount (${amount}) must equal invoice.total_amount (${invoice.total_amount})`
    );
    e.code = "AMOUNT_MISMATCH";
    throw e;
  }

  const updRes = await client.query<RentInvoiceRow>(
    `
    UPDATE public.rent_invoices
    SET
      status = 'paid'::invoice_status,
      paid_amount = $2::numeric,
      paid_at = NOW()
    WHERE id = $1::uuid
      AND deleted_at IS NULL
    RETURNING ${RENT_INVOICE_SELECT};
    `,
    [args.invoiceId, amount]
  );

  const updated = updRes.rows[0]!;
  await recordRentPaymentAndLedger(client, updated, args.paymentMethod, Number(amount));

  return { row: updated, alreadyPaid: false };
}
TS

echo "✅ wrote src/services/rent_invoices.service.ts"

# --- 3) Patch routes (type client as PoolClient + keep applyDbContext correct) ---
cat > src/routes/rent_invoices.ts <<'TS'
import type { FastifyInstance } from "fastify";
import type { PoolClient } from "pg";
import { z } from "zod";
import {
  generateRentInvoiceForTenancy,
  getRentInvoices,
  payRentInvoice,
} from "../services/rent_invoices.service.js";
import {
  GenerateRentInvoiceBodySchema,
  ListRentInvoicesQuerySchema,
  PayRentInvoiceBodySchema,
} from "../schemas/rent_invoices.schema.js";

type AuthReq = {
  user?: { sub?: string; role?: string };
  jwtVerify?: () => Promise<void>;
  params?: any;
  body?: any;
  query?: any;
  headers?: any;
};

async function ensureAuth(app: FastifyInstance, req: any, reply: any) {
  try {
    if (typeof req?.jwtVerify === "function") {
      await req.jwtVerify();
      return null;
    }
    if (typeof (app as any).authenticate === "function") {
      await (app as any).authenticate(req, reply);
      return null;
    }
    return reply.code(500).send({
      ok: false,
      error: "JWT_NOT_CONFIGURED",
      message: "jwtVerify/app.authenticate not found. Ensure JWT plugin is registered.",
    });
  } catch {
    return reply.code(401).send({ ok: false, error: "UNAUTHORIZED", message: "Unauthorized" });
  }
}

function requireUserId(req: any) {
  const sub = req?.user?.sub;
  if (!sub) {
    const e: any = new Error("Missing authenticated user id (req.user.sub)");
    e.code = "USER_ID_MISSING";
    throw e;
  }
  return sub as string;
}

async function applyDbContext(client: PoolClient, req: any) {
  // Header is x-organization-id, but DB setting key uses underscore: x_organization_id
  const orgId =
    req?.headers?.["x-organization-id"] ||
    req?.headers?.["X-Organization-Id"] ||
    req?.headers?.["x-organization-id".toLowerCase()];

  const userId = req?.user?.sub || "";
  const role = req?.user?.role || "";

  if (!orgId) {
    const e: any = new Error("Missing x-organization-id header");
    e.code = "ORG_ID_MISSING";
    throw e;
  }

  const org = String(orgId);
  const uid = userId ? String(userId) : "";
  const r = role ? String(role) : "";

  // ORG context (matches current_organization_uuid())
  await client.query("SELECT set_config('request.header.x_organization_id', $1, true);", [org]);
  await client.query("SELECT set_config('request.jwt.claim.org', $1, true);", [org]);
  await client.query("SELECT set_config('request.jwt.claims.org', $1, true);", [org]);
  await client.query("SELECT set_config('request.jwt.claim.organization_id', $1, true);", [org]);
  await client.query("SELECT set_config('app.organization_id', $1, true);", [org]);

  // extra aliases (harmless)
  await client.query("SELECT set_config('app.org_id', $1, true);", [org]);
  await client.query("SELECT set_config('rentease.organization_id', $1, true);", [org]);
  await client.query("SELECT set_config('rentease.org_id', $1, true);", [org]);

  // USER context
  await client.query("SELECT set_config('request.jwt.claim.sub', $1, true);", [uid]);
  await client.query("SELECT set_config('request.user_id', $1, true);", [uid]);
  await client.query("SELECT set_config('app.user_id', $1, true);", [uid]);
  await client.query("SELECT set_config('rentease.user_id', $1, true);", [uid]);

  await client.query("SELECT set_config('request.user_role', $1, true);", [r]);
  await client.query("SELECT set_config('app.user_role', $1, true);", [r]);
  await client.query("SELECT set_config('rentease.user_role', $1, true);", [r]);
}

export async function rentInvoicesRoutes(app: FastifyInstance) {
  // Generate invoice for a tenancy
  app.post("/v1/tenancies/:id/rent-invoices/generate", async (req, reply) => {
    const authResp = await ensureAuth(app, req, reply);
    if (authResp) return authResp;

    try {
      requireUserId(req);

      const params = z.object({ id: z.string().uuid() }).parse((req as any).params);
      const body = GenerateRentInvoiceBodySchema.parse((req as any).body);

      const pgAny: any = (app as any).pg;
      if (!pgAny?.connect) {
        return reply.code(500).send({
          ok: false,
          error: "PG_NOT_CONFIGURED",
          message: "Fastify pg plugin not found at app.pg",
        });
      }

      const client = (await pgAny.connect()) as PoolClient;
      try {
        await applyDbContext(client, req);
        await client.query("BEGIN");

        const res = await generateRentInvoiceForTenancy(client, {
          tenancyId: params.id,
          periodStart: body.periodStart,
          periodEnd: body.periodEnd,
          dueDate: body.dueDate,
          subtotal: body.subtotal,
          lateFeeAmount: body.lateFeeAmount,
          currency: body.currency,
          status: body.status,
          notes: body.notes,
        });

        await client.query("COMMIT");
        return reply.send({ ok: true, reused: res.reused, data: res.row });
      } catch (err: any) {
        try { await client.query("ROLLBACK"); } catch {}
        return reply.code(500).send({
          ok: false,
          error: err?.code ?? "INTERNAL_ERROR",
          message: err?.message ?? String(err),
        });
      } finally {
        client.release();
      }
    } catch (err: any) {
      return reply.code(400).send({
        ok: false,
        error: err?.code ?? "BAD_REQUEST",
        message: err?.message ?? String(err),
      });
    }
  });

  // List invoices
  app.get("/v1/rent-invoices", async (req, reply) => {
    const authResp = await ensureAuth(app, req, reply);
    if (authResp) return authResp;

    try {
      requireUserId(req);
      const q = ListRentInvoicesQuerySchema.parse((req as any).query);

      const pgAny: any = (app as any).pg;
      if (!pgAny?.connect) {
        return reply.code(500).send({
          ok: false,
          error: "PG_NOT_CONFIGURED",
          message: "Fastify pg plugin not found at app.pg",
        });
      }

      const client = (await pgAny.connect()) as PoolClient;
      try {
        await applyDbContext(client, req);

        const data = await getRentInvoices(client, {
          limit: q.limit,
          offset: q.offset,
          tenancyId: q.tenancyId,
          tenantId: q.tenantId,
          propertyId: q.propertyId,
          status: q.status,
        });

        return reply.send({ ok: true, data, paging: { limit: q.limit, offset: q.offset } });
      } catch (err: any) {
        return reply.code(500).send({
          ok: false,
          error: err?.code ?? "INTERNAL_ERROR",
          message: err?.message ?? String(err),
        });
      } finally {
        client.release();
      }
    } catch (err: any) {
      return reply.code(400).send({
        ok: false,
        error: err?.code ?? "BAD_REQUEST",
        message: err?.message ?? String(err),
      });
    }
  });

  // Pay invoice (admin-only for now)
  app.post("/v1/rent-invoices/:id/pay", async (req, reply) => {
    const authResp = await ensureAuth(app, req, reply);
    if (authResp) return authResp;

    const anyReq = req as unknown as AuthReq;
    const userId = anyReq.user?.sub;
    if (!userId) {
      return reply.code(401).send({
        ok: false,
        error: "USER_ID_MISSING",
        message: "Missing authenticated user id (req.user.sub)",
      });
    }

    const pgAny: any = (app as any).pg;
    if (!pgAny?.connect) {
      return reply.code(500).send({
        ok: false,
        error: "PG_NOT_CONFIGURED",
        message: "Fastify pg plugin not found at app.pg",
      });
    }

    const params = z.object({ id: z.string().uuid() }).parse((anyReq as any).params);
    const body = PayRentInvoiceBodySchema.parse((anyReq as any).body);

    const client = (await pgAny.connect()) as PoolClient;
    try {
      // role is used by DB is_admin() via set_config
      anyReq.user = anyReq.user ?? {};
      anyReq.user.role = anyReq.user.role ?? "admin";
      await applyDbContext(client, req);

      // DB-role check (admin only for now)
      const roleRes = await client.query<{ role: string }>(
        "select role from public.users where id = $1::uuid limit 1;",
        [userId]
      );
      const dbRole = roleRes.rows[0]?.role;

      if (dbRole !== "admin") {
        return reply.code(403).send({
          ok: false,
          error: "FORBIDDEN",
          message: "Admin only for now (policy requires admin or service role).",
        });
      }

      await client.query("BEGIN");

      const res = await payRentInvoice(client, {
        invoiceId: params.id,
        paymentMethod: body.paymentMethod,
        amount: body.amount,
      });

      await client.query("COMMIT");
      return reply.send({ ok: true, alreadyPaid: res.alreadyPaid, data: res.row });
    } catch (err: any) {
      try { await client.query("ROLLBACK"); } catch {}
      return reply.code(500).send({
        ok: false,
        error: err?.code ?? "INTERNAL_ERROR",
        message: err?.message ?? String(err),
      });
    } finally {
      client.release();
    }
  });
}
TS

echo "✅ wrote src/routes/rent_invoices.ts"

echo ""
echo "== DONE =="
echo "➡️ Restart: npm run dev"
echo "➡️ Test:"
echo "   1) generate invoice"
echo "   2) pay invoice"
echo "   3) verify:"
echo "      psql -d \"\$DB_NAME\" -c \"select * from public.rent_payments order by created_at desc limit 3;\""
echo "      psql -d \"\$DB_NAME\" -c \"select * from public.rent_invoice_payments order by created_at desc limit 3;\""
echo "      psql -d \"\$DB_NAME\" -c \"select * from public.wallet_transactions where reference_type='rent_invoice' order by created_at desc limit 5;\""
