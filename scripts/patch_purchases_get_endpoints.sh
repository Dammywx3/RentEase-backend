#!/usr/bin/env bash
set -eo pipefail

ROUTES_FILE="src/routes/purchases.routes.ts"
INDEX_FILE="src/routes/index.ts"

mkdir -p scripts/.bak
ts="$(date +%Y%m%d_%H%M%S)"

# --- sanity checks ---
[ -f "$ROUTES_FILE" ] || { echo "❌ Missing: $ROUTES_FILE"; exit 1; }
[ -f "$INDEX_FILE" ] || { echo "❌ Missing: $INDEX_FILE"; exit 1; }

cp "$ROUTES_FILE" "scripts/.bak/purchases.routes.ts.bak.$ts"
cp "$INDEX_FILE"  "scripts/.bak/index.ts.bak.$ts"
echo "✅ backups -> scripts/.bak (.${ts})"

# --- 1) Ensure purchases routes are registered in src/routes/index.ts ---
python3 - <<'PY'
from pathlib import Path
p = Path("src/routes/index.ts")
s = p.read_text()

if "purchasesRoutes" not in s:
    # add import
    # place after existing imports
    lines = s.splitlines(True)
    insert_at = 0
    for i,l in enumerate(lines):
        if l.startswith("import "):
            insert_at = i+1
    lines.insert(insert_at, 'import purchasesRoutes from "./purchases.routes.js";\n')
    s = "".join(lines)

# add register call inside registerRoutes(app)
if "await app.register(purchasesRoutes);" not in s:
    # put near other route registrations (after rentInvoicesRoutes is fine)
    marker = "await app.register(rentInvoicesRoutes);"
    idx = s.find(marker)
    if idx == -1:
        raise SystemExit("❌ Could not find where to insert purchasesRoutes registration")
    insert_pos = idx + len(marker)
    s = s[:insert_pos] + "\n  await app.register(purchasesRoutes);\n" + s[insert_pos:]

p.write_text(s)
print("✅ PATCHED:", str(p))
PY

# --- 2) Add GET endpoints to purchases.routes.ts ---
python3 - <<'PY'
from pathlib import Path
p = Path("src/routes/purchases.routes.ts")
s = p.read_text()

if "GET /purchases" in s and "GET /purchases/:purchaseId" in s:
    print("✅ purchases.routes.ts already has GET endpoints (skipping)")
    raise SystemExit(0)

# Find inside the default export function body start
needle = "export default async function purchasesRoutes"
pos = s.find(needle)
if pos == -1:
    raise SystemExit("❌ Could not find purchasesRoutes export")

# Find first "fastify" usage point to insert GET routes near top, before POST pay ideally.
# We'll insert right after function opening brace "{"
brace = s.find("{", pos)
if brace == -1:
    raise SystemExit("❌ Could not find opening brace for purchasesRoutes function")

insert_point = brace + 1

get_block = r"""

  /**
   * GET /purchases  (list)
   * Requires: x-organization-id header
   */
  fastify.get("/purchases", async (request, reply) => {
    const orgId = String(request.headers["x-organization-id"] || "");
    if (!orgId) {
      return reply.code(400).send({
        ok: false,
        error: "ORG_REQUIRED",
        message: "x-organization-id required",
      });
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
          pp.last_payment_id::text as last_payment_id,
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
              and wt.txn_type in (
                'credit_payee'::wallet_transaction_type,
                'credit_platform_fee'::wallet_transaction_type
              )
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

  /**
   * GET /purchases/:purchaseId  (detail)
   * Requires: x-organization-id header
   */
  fastify.get<{ Params: { purchaseId: string } }>(
    "/purchases/:purchaseId",
    async (request, reply) => {
      const orgId = String(request.headers["x-organization-id"] || "");
      if (!orgId) {
        return reply.code(400).send({
          ok: false,
          error: "ORG_REQUIRED",
          message: "x-organization-id required",
        });
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
        if (!row) {
          return reply.code(404).send({
            ok: false,
            error: "NOT_FOUND",
            message: "Purchase not found",
          });
        }

        return reply.send({ ok: true, data: row });
      } finally {
        client.release();
      }
    }
  );

"""
s = s[:insert_point] + get_block + s[insert_point:]

p.write_text(s)
print("✅ PATCHED:", str(p))
PY

echo ""
echo "✅ DONE"
echo "NEXT:"
echo "  1) Restart server: npm run dev"
echo "  2) Test list:"
echo "     curl -sS \"$API/v1/purchases\" -H \"authorization: Bearer \$TOKEN\" -H \"x-organization-id: \$ORG_ID\" | jq"
echo "  3) Test detail:"
echo "     curl -sS \"$API/v1/purchases/\$PURCHASE_ID\" -H \"authorization: Bearer \$TOKEN\" -H \"x-organization-id: \$ORG_ID\" | jq"
