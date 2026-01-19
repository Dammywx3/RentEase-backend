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

# ------------------------------------------------------------
# (A) Patch SERVICE: set purchase payment milestone fields
# ------------------------------------------------------------
# 1) Remove any broken placeholder "WHERE id = ::uuid" blocks if they exist.
perl -0777 -i -pe '
  $t =~ s/WHERE\s+id\s*=\s*::uuid/WHERE id = $1::uuid/gs;
' "$SERVICE"

# 2) Ensure we update milestones after ledger credits (creditPlatformFee + creditPayee)
if ! grep -q "purchase payment milestones" "$SERVICE"; then
  perl -0777 -i -pe '
    $needle = qr/await\s+creditPayee\([\s\S]*?\);\s*/;
    if ($t =~ $needle) {
      $t =~ s/$needle/$&\n  \/\/ 3) Update purchase payment milestones (no lifecycle enum change)\n  await client.query(\n    `\n    UPDATE public.property_purchases\n    SET\n      payment_status = '\''paid'\''::purchase_payment_status,\n      paid_at = COALESCE(paid_at, NOW()),\n      paid_amount = $1::numeric,\n      updated_at = NOW()\n    WHERE id = $2::uuid\n      AND organization_id = $3::uuid\n      AND deleted_at IS NULL;\n    `,\n    [amount, purchase.id, args.organizationId]\n  );\n\n/s;
    }
  ' "$SERVICE"
  echo "✅ Added milestone update to $SERVICE"
else
  echo "ℹ️ Milestone update already present in $SERVICE (skipping)"
fi

# Guard against old invalid token still present
if grep -n "WHERE id = ::uuid" "$SERVICE" >/dev/null 2>&1; then
  echo "❌ Patch incomplete: still found invalid 'WHERE id = ::uuid' in $SERVICE"
  exit 1
fi

# ------------------------------------------------------------
# (B) Patch ROUTE: add GET list + GET detail endpoints
# ------------------------------------------------------------
if ! grep -q 'GET /purchases (list)' "$ROUTE"; then
  perl -0777 -i -pe '
    $inject = qq@\n  // ------------------------------------------------------------\n  // GET /purchases (list)\n  // ------------------------------------------------------------\n  fastify.get(\"/purchases\", async (request, reply) => {\n    const orgId = String(request.headers[\"x-organization-id\"] || \"\");\n    if (!orgId) {\n      return reply.code(400).send({ ok: false, error: \"ORG_REQUIRED\", message: \"x-organization-id required\" });\n    }\n\n    const client = await fastify.pg.connect();\n    try {\n      const { rows } = await client.query(\n        `\n        select\n          pp.id,\n          pp.organization_id,\n          pp.property_id,\n          pp.listing_id,\n          pp.buyer_id,\n          pp.seller_id,\n          pp.agreed_price::text as agreed_price,\n          pp.currency,\n          pp.status::text as status,\n          pp.payment_status::text as payment_status,\n          pp.paid_at::text as paid_at,\n          pp.paid_amount::text as paid_amount,\n          pp.created_at::text as created_at,\n          pp.updated_at::text as updated_at,\n\n          exists (\n            select 1 from public.property_purchase_payments ppp\n            where ppp.purchase_id = pp.id\n          ) as has_payment_link,\n\n          (\n            select count(*)\n            from public.wallet_transactions wt\n            where wt.reference_type=\'purchase\'\n              and wt.reference_id=pp.id\n              and wt.txn_type in (\'credit_payee\'::wallet_transaction_type,\'credit_platform_fee\'::wallet_transaction_type)\n          ) as ledger_txn_count\n        from public.property_purchases pp\n        where pp.organization_id = $1::uuid\n          and pp.deleted_at is null\n        order by pp.created_at desc\n        limit 50;\n        `,\n        [orgId]\n      );\n\n      return reply.send({ ok: true, data: rows });\n    } finally {\n      client.release();\n    }\n  });\n\n  // ------------------------------------------------------------\n  // GET /purchases/:purchaseId (detail)\n  // ------------------------------------------------------------\n  fastify.get<{ Params: { purchaseId: string } }>(\"/purchases/:purchaseId\", async (request, reply) => {\n    const orgId = String(request.headers[\"x-organization-id\"] || \"\");\n    if (!orgId) {\n      return reply.code(400).send({ ok: false, error: \"ORG_REQUIRED\", message: \"x-organization-id required\" });\n    }\n\n    const { purchaseId } = request.params;\n\n    const client = await fastify.pg.connect();\n    try {\n      const { rows } = await client.query(\n        `\n        select\n          pp.*,\n          pp.status::text as status_text,\n          pp.payment_status::text as payment_status_text,\n\n          coalesce((\n            select jsonb_agg(jsonb_build_object(\n              \'payment_id\', p.id,\n              \'amount\', p.amount,\n              \'currency\', p.currency,\n              \'status\', p.status::text,\n              \'transaction_reference\', p.transaction_reference,\n              \'created_at\', p.created_at\n            ) order by p.created_at desc)\n            from public.property_purchase_payments link\n            join public.payments p on p.id = link.payment_id\n            where link.purchase_id = pp.id\n          ), \'[]\'::jsonb) as payments,\n\n          coalesce((\n            select jsonb_agg(jsonb_build_object(\n              \'txn_type\', wt.txn_type::text,\n              \'amount\', wt.amount,\n              \'currency\', wt.currency,\n              \'created_at\', wt.created_at\n            ) order by wt.created_at asc)\n            from public.wallet_transactions wt\n            where wt.reference_type=\'purchase\'\n              and wt.reference_id=pp.id\n          ), \'[]\'::jsonb) as ledger\n        from public.property_purchases pp\n        where pp.id = $1::uuid\n          and pp.organization_id = $2::uuid\n          and pp.deleted_at is null\n        limit 1;\n        `,\n        [purchaseId, orgId]\n      );\n\n      const row = rows[0];\n      if (!row) {\n        return reply.code(404).send({ ok: false, error: \"NOT_FOUND\", message: \"Purchase not found\" });\n      }\n\n      return reply.send({ ok: true, data: row });\n    } finally {\n      client.release();\n    }\n  });\n@;

    # Insert GET routes before the existing pay route definition
    $t =~ s/(\"\\/purchases\\/:purchaseId\\/pay\")/$inject\n\n  $1/s;
  ' "$ROUTE"
  echo "✅ Added GET endpoints to $ROUTE"
else
  echo "ℹ️ GET endpoints already exist in $ROUTE (skipping)"
fi

# ------------------------------------------------------------
# (C) Register purchases routes in routes/index.ts (prefix /v1)
# ------------------------------------------------------------
if ! grep -q 'purchasesRoutes' "$INDEX"; then
  # add import
  perl -0777 -i -pe '
    $t =~ s/(import\s+\{\s*rentInvoicesRoutes\s*\}\s+from\s+"\.\/rent_invoices\.js";\s*)/$1import purchasesRoutes from "\.\/purchases\.routes\.js";\n/s;
  ' "$INDEX"

  # register with prefix /v1 (since purchases.routes.ts defines "/purchases/..")
  perl -0777 -i -pe '
    if ($t !~ /await\s+app\.register\(purchasesRoutes,\s*\{\s*prefix:\s*"\/v1"\s*\}\s*\)/) {
      $t =~ s/(await\s+app\.register\(applicationRoutes\);\s*\n)/$1\n  \/\/ Purchases (buy flow)\n  await app.register(purchasesRoutes, { prefix: \"\/v1\" });\n/s;
    }
  ' "$INDEX"

  echo "✅ Registered purchasesRoutes in $INDEX"
else
  echo "ℹ️ purchasesRoutes already referenced in $INDEX (skipping)"
fi

echo ""
echo "✅ ALL PATCHES APPLIED"
echo "NEXT:"
echo "  1) Restart: npm run dev"
echo "  2) Test GET list:"
echo "     curl -sS \"\$API/v1/purchases\" -H \"authorization: Bearer \$TOKEN\" -H \"x-organization-id: \$ORG_ID\" | jq"
echo "  3) Test GET detail:"
echo "     curl -sS \"\$API/v1/purchases/\$PURCHASE_ID\" -H \"authorization: Bearer \$TOKEN\" -H \"x-organization-id: \$ORG_ID\" | jq"
echo "  4) Verify milestones:"
echo "     PAGER=cat psql -d \"\$DB_NAME\" -X -c \"select id, status, payment_status, paid_at, paid_amount, last_payment_id from public.property_purchases where id='\$PURCHASE_ID'::uuid;\""
