#!/usr/bin/env bash
set -eo pipefail

SERVICE="src/services/purchase_payments.service.ts"
ROUTE="src/routes/purchases.routes.ts"
INDEX="src/routes/index.ts"

need() { [ -f "$1" ] || { echo "❌ Missing file: $1"; exit 1; }; }

need "$SERVICE"
need "$ROUTE"
need "$INDEX"

mkdir -p scripts/.bak
ts="$(date +%Y%m%d_%H%M%S)"
cp "$SERVICE" "scripts/.bak/purchase_payments.service.ts.bak.$ts"
cp "$ROUTE"   "scripts/.bak/purchases.routes.ts.bak.$ts"
cp "$INDEX"   "scripts/.bak/routes.index.ts.bak.$ts"
echo "✅ backups saved in scripts/.bak (.$ts)"

python3 - <<'PY'
from pathlib import Path

SERVICE = Path("src/services/purchase_payments.service.ts")
ROUTE   = Path("src/routes/purchases.routes.ts")
INDEX   = Path("src/routes/index.ts")

# -----------------------------
# A) SERVICE: milestones + fix invalid ::uuid placeholders
# -----------------------------
s = SERVICE.read_text()

# Fix the known bad pattern if it exists anywhere
s = s.replace("WHERE id = ::uuid", "WHERE id = $1::uuid")
s = s.replace("AND organization_id = ::uuid", "AND organization_id = $2::uuid")

# Ensure milestone update exists after ledger credits
milestone_marker = "Update purchase payment milestones"
if milestone_marker not in s:
    needle = "await creditPayee"
    idx = s.find(needle)
    if idx == -1:
        raise SystemExit("❌ Could not find creditPayee(...) call to insert milestone update.")
    # Insert AFTER the first "await creditPayee(...);" statement block end
    end = s.find(");", idx)
    if end == -1:
        raise SystemExit("❌ Could not find end of creditPayee(...) call.")
    end = s.find(");", end)  # second ); in case nested
    if end == -1:
        raise SystemExit("❌ Could not locate insertion point after creditPayee(...).")

    insert = r"""
  // 3) Update purchase payment milestones (no lifecycle enum change)
  await client.query(
    `
    UPDATE public.property_purchases
    SET
      payment_status = 'paid'::purchase_payment_status,
      paid_at = COALESCE(paid_at, NOW()),
      paid_amount = $1::numeric,
      updated_at = NOW()
    WHERE id = $2::uuid
      AND organization_id = $3::uuid
      AND deleted_at IS NULL;
    `,
    [amount, purchase.id, args.organizationId]
  );

"""
    s = s[:end+2] + insert + s[end+2:]

# Guard: must not contain invalid token now
if "WHERE id = ::uuid" in s:
    raise SystemExit("❌ Still found invalid 'WHERE id = ::uuid' in purchase_payments.service.ts")

SERVICE.write_text(s)
print("✅ PATCHED:", SERVICE)

# -----------------------------
# B) ROUTE: add GET list + GET detail endpoints
# -----------------------------
r = ROUTE.read_text()

if 'fastify.get("/purchases"' not in r:
    # Insert GET routes before pay route
    anchor = '("/purchases/:purchaseId/pay"'
    aidx = r.find(anchor)
    if aidx == -1:
        # alternative anchor (some files use >("/purchases/:purchaseId/pay"
        anchor = '>/purchases/:purchaseId/pay'
        aidx = r.find(anchor)
    if aidx == -1:
        # fallback: insert before last closing brace of the exported function
        aidx = r.rfind("}")
        if aidx == -1:
            raise SystemExit("❌ Could not find insertion anchor in purchases.routes.ts")

    get_block = r"""
  // ------------------------------------------------------------
  // GET /purchases (list)
  // ------------------------------------------------------------
  fastify.get("/purchases", async (request, reply) => {
    const orgId = String(request.headers["x-organization-id"] || "");
    if (!orgId) {
      return reply.code(400).send({ ok: false, error: "ORG_REQUIRED", message: "x-organization-id required" });
    }

    const client = await fastify.pg.connect();
    try {
      const { rows } = await client.query(
        `
        select
          pp.id,
          pp.organization_id,
          pp.property_id,
          pp.listing_id,
          pp.buyer_id,
          pp.seller_id,
          pp.agreed_price::text as agreed_price,
          pp.currency,
          pp.status::text as status,
          pp.payment_status::text as payment_status,
          pp.paid_at::text as paid_at,
          pp.paid_amount::text as paid_amount,
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
              and wt.txn_type in ('credit_payee'::wallet_transaction_type,'credit_platform_fee'::wallet_transaction_type)
          ) as ledger_txn_count
        from public.property_purchases pp
        where pp.organization_id = $1::uuid
          and pp.deleted_at is null
        order by pp.created_at desc
        limit 50;
        `,
        [orgId]
      );

      return reply.send({ ok: true, data: rows });
    } finally {
      client.release();
    }
  });

  // ------------------------------------------------------------
  // GET /purchases/:purchaseId (detail)
  // ------------------------------------------------------------
  fastify.get<{ Params: { purchaseId: string } }>("/purchases/:purchaseId", async (request, reply) => {
    const orgId = String(request.headers["x-organization-id"] || "");
    if (!orgId) {
      return reply.code(400).send({ ok: false, error: "ORG_REQUIRED", message: "x-organization-id required" });
    }

    const { purchaseId } = request.params;

    const client = await fastify.pg.connect();
    try {
      const { rows } = await client.query(
        `
        select
          pp.*,
          pp.status::text as status_text,
          pp.payment_status::text as payment_status_text,

          coalesce((
            select jsonb_agg(jsonb_build_object(
              'payment_id', p.id,
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
      if (!row) return reply.code(404).send({ ok: false, error: "NOT_FOUND", message: "Purchase not found" });

      return reply.send({ ok: true, data: row });
    } finally {
      client.release();
    }
  });

"""
    r = r[:aidx] + get_block + r[aidx:]

ROUTE.write_text(r)
print("✅ PATCHED:", ROUTE)

# -----------------------------
# C) INDEX: register purchases routes under /v1
# -----------------------------
i = INDEX.read_text()

if 'purchasesRoutes' not in i:
    # Add import near other route imports
    if 'rentInvoicesRoutes' in i and 'purchases.routes.js' not in i:
        i = i.replace(
            'import { rentInvoicesRoutes } from "./rent_invoices.js";',
            'import { rentInvoicesRoutes } from "./rent_invoices.js";\nimport purchasesRoutes from "./purchases.routes.js";'
        )

    # Register it in registerRoutes()
    if 'await app.register(purchasesRoutes' not in i:
        # Put near end after applicationsRoutes registration
        marker = "await app.register(applicationRoutes);"
        if marker in i:
            i = i.replace(marker, marker + '\n\n  // Purchases (buy flow)\n  await app.register(purchasesRoutes, { prefix: "/v1" });\n')
        else:
            # fallback: append before closing brace
            pos = i.rfind("}")
            i = i[:pos] + '\n  // Purchases (buy flow)\n  await app.register(purchasesRoutes, { prefix: "/v1" });\n' + i[pos:]

INDEX.write_text(i)
print("✅ PATCHED:", INDEX)
PY

echo ""
echo "✅ DONE"
echo "NEXT:"
echo "  1) Restart server: npm run dev"
echo "  2) Test list:"
echo "     curl -sS \"\$API/v1/purchases\" -H \"authorization: Bearer \$TOKEN\" -H \"x-organization-id: \$ORG_ID\" | jq"
echo "  3) Test detail:"
echo "     curl -sS \"\$API/v1/purchases/\$PURCHASE_ID\" -H \"authorization: Bearer \$TOKEN\" -H \"x-organization-id: \$ORG_ID\" | jq"
echo "  4) Verify milestones:"
echo "     PAGER=cat psql -d \"\$DB_NAME\" -X -c \"select id, status, payment_status, paid_at, paid_amount, last_payment_id from public.property_purchases where id='\$PURCHASE_ID'::uuid;\""
