#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
DB_NAME="${DB_NAME:-rentease}"

echo "ROOT=$ROOT"
echo "DB_NAME=$DB_NAME"

# -----------------------------
# 1) Run SQL migration (already fixed)
# -----------------------------
SQL_FILE="scripts/sql/2026_01_16_purchase_refunds.sql"
if [[ ! -f "$SQL_FILE" ]]; then
  echo "❌ Missing $SQL_FILE"
  exit 1
fi

echo "== Running SQL: $SQL_FILE =="
psql -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$SQL_FILE"
echo "✅ SQL applied"

# -----------------------------
# 2) Patch ledger.service.ts to add debit helpers (if missing)
# -----------------------------
LEDGER_FILE="src/services/ledger.service.ts"
if [[ ! -f "$LEDGER_FILE" ]]; then
  echo "❌ Missing $LEDGER_FILE"
  exit 1
fi

if ! grep -q "export async function debitPayee" "$LEDGER_FILE"; then
  echo "== Patching ledger.service.ts (add debitPayee/debitPlatformFee) =="
  cp "$LEDGER_FILE" "scripts/.bak/ledger.service.ts.bak.$(date +%Y%m%d_%H%M%S)"

  cat >> "$LEDGER_FILE" <<'TS'

/**
 * Refund / reversal helpers (purchase refund flow)
 * Uses wallet_transactions with txn_type debit_* and reference_type 'purchase_refund' (or any reference you pass).
 */

export async function debitPlatformFee(
  client: import("pg").PoolClient,
  args: {
    organizationId: string;
    referenceType: string;
    referenceId: string;
    amount: number;
    currency: string;
    note?: string | null;
  }
) {
  // Find platform wallet account in this org
  const { rows: waRows } = await client.query<{ id: string }>(
    `
    select id
    from public.wallet_accounts
    where organization_id = $1::uuid
      and is_platform_wallet = true
    limit 1;
    `,
    [args.organizationId]
  );

  const platformWalletId = waRows[0]?.id;
  if (!platformWalletId) {
    const e: any = new Error("Platform wallet not found");
    e.code = "PLATFORM_WALLET_NOT_FOUND";
    throw e;
  }

  await client.query(
    `
    insert into public.wallet_transactions
      (organization_id, wallet_account_id, txn_type, reference_type, reference_id, amount, currency, note)
    values
      ($1::uuid, $2::uuid, 'debit_platform_fee'::wallet_transaction_type, $3::text, $4::uuid, $5::numeric, $6::varchar, $7::text)
    on conflict do nothing;
    `,
    [
      args.organizationId,
      platformWalletId,
      args.referenceType,
      args.referenceId,
      args.amount,
      args.currency,
      args.note ?? null,
    ]
  );
}

export async function debitPayee(
  client: import("pg").PoolClient,
  args: {
    organizationId: string;
    payeeUserId: string;
    referenceType: string;
    referenceId: string;
    amount: number;
    currency: string;
    note?: string | null;
  }
) {
  // Find payee wallet account
  const { rows: waRows } = await client.query<{ id: string }>(
    `
    select id
    from public.wallet_accounts
    where organization_id = $1::uuid
      and user_id = $2::uuid
      and is_platform_wallet = false
    limit 1;
    `,
    [args.organizationId, args.payeeUserId]
  );

  const payeeWalletId = waRows[0]?.id;
  if (!payeeWalletId) {
    const e: any = new Error("Payee wallet not found");
    e.code = "PAYEE_WALLET_NOT_FOUND";
    throw e;
  }

  await client.query(
    `
    insert into public.wallet_transactions
      (organization_id, wallet_account_id, txn_type, reference_type, reference_id, amount, currency, note)
    values
      ($1::uuid, $2::uuid, 'debit_payee'::wallet_transaction_type, $3::text, $4::uuid, $5::numeric, $6::varchar, $7::text)
    on conflict do nothing;
    `,
    [
      args.organizationId,
      payeeWalletId,
      args.referenceType,
      args.referenceId,
      args.amount,
      args.currency,
      args.note ?? null,
    ]
  );
}
TS

  echo "✅ Patched $LEDGER_FILE"
else
  echo "ℹ️ ledger.service.ts already has debit helpers (skipping)"
fi

# -----------------------------
# 3) Create refund service (src/services/purchase_refunds.service.ts)
# -----------------------------
REFUND_SVC="src/services/purchase_refunds.service.ts"
if [[ ! -f "$REFUND_SVC" ]]; then
  echo "== Creating refund service: $REFUND_SVC =="
  cat > "$REFUND_SVC" <<'TS'
import type { PoolClient } from "pg";
import { computePlatformFeeSplit } from "../config/fees.config.js";
import { debitPayee, debitPlatformFee } from "./ledger.service.js";
import { getPropertyPurchase } from "./purchase_payments.service.js";

export type PurchaseRefundMethod = "card" | "bank_transfer" | "wallet";

export async function refundPropertyPurchase(
  client: PoolClient,
  args: {
    organizationId: string;
    purchaseId: string;
    refundMethod: PurchaseRefundMethod;
    amount?: number | null; // defaults to agreed_price
  }
) {
  const purchase = await getPropertyPurchase(client, {
    organizationId: args.organizationId,
    purchaseId: args.purchaseId,
  });

  const agreed = Number(purchase.agreed_price);
  const amount = typeof args.amount === "number" ? args.amount : agreed;
  const currency = (purchase.currency ?? "USD") || "USD";

  // Must already be paid (or at least have ledger credits) to refund meaningfully
  const chk = await client.query<{ txn_type: string; cnt: string }>(
    `
    SELECT wt.txn_type::text AS txn_type, count(*)::text AS cnt
    FROM public.wallet_transactions wt
    WHERE wt.organization_id = $1::uuid
      AND wt.reference_type = 'purchase'
      AND wt.reference_id = $2::uuid
      AND wt.txn_type IN ('credit_payee'::wallet_transaction_type, 'credit_platform_fee'::wallet_transaction_type)
    GROUP BY wt.txn_type
    `,
    [args.organizationId, purchase.id]
  );

  const hasPayee = chk.rows.some((r) => r.txn_type === "credit_payee" && Number(r.cnt) > 0);
  const hasFee = chk.rows.some((r) => r.txn_type === "credit_platform_fee" && Number(r.cnt) > 0);

  if (!(hasPayee && hasFee)) {
    const e: any = new Error("Cannot refund: purchase not paid yet (missing ledger credits)");
    e.code = "PURCHASE_NOT_PAID";
    throw e;
  }

  // Idempotent: if already refunded milestones set, treat as already refunded
  const already = await client.query<{ ok: boolean }>(
    `
    select (pp.payment_status::text = 'refunded') as ok
    from public.property_purchases pp
    where pp.id = $1::uuid and pp.organization_id = $2::uuid and pp.deleted_at is null
    limit 1;
    `,
    [purchase.id, args.organizationId]
  );

  if (already.rows?.[0]?.ok) {
    const updated = await getPropertyPurchase(client, {
      organizationId: args.organizationId,
      purchaseId: purchase.id,
    });
    return { purchase: updated, alreadyRefunded: true };
  }

  // Compute how it was split at pay-time (same rule)
  const split = computePlatformFeeSplit({
    paymentKind: "buy",
    amount,
    currency,
  });

  // Reversal ledger entries: use a separate reference_type to avoid clashing unique constraints
  const refundRefType = "purchase_refund";

  await debitPlatformFee(client, {
    organizationId: args.organizationId,
    referenceType: refundRefType,
    referenceId: purchase.id,
    amount: split.platformFee,
    currency,
    note: `Refund reversal of platform fee for purchase ${purchase.id}`,
  });

  await debitPayee(client, {
    organizationId: args.organizationId,
    payeeUserId: purchase.seller_id,
    referenceType: refundRefType,
    referenceId: purchase.id,
    amount: split.payeeNet,
    currency,
    note: `Refund reversal of payee net for purchase ${purchase.id}`,
  });

  // Update refund milestone fields
  await client.query(
    `
    update public.property_purchases
    set
      payment_status = 'refunded'::purchase_payment_status,
      refunded_at = coalesce(refunded_at, now()),
      refunded_amount = coalesce(refunded_amount, 0) + $1::numeric,
      updated_at = now()
    where id = $2::uuid
      and organization_id = $3::uuid
      and deleted_at is null;
    `,
    [amount, purchase.id, args.organizationId]
  );

  const updated = await getPropertyPurchase(client, {
    organizationId: args.organizationId,
    purchaseId: purchase.id,
  });

  return { purchase: updated, alreadyRefunded: false, refundAmount: amount };
}
TS
  echo "✅ Wrote $REFUND_SVC"
else
  echo "ℹ️ Refund service already exists (skipping)"
fi

# -----------------------------
# 4) Patch purchases.routes.ts to add POST /purchases/:id/refund (if missing)
# -----------------------------
ROUTES_FILE="src/routes/purchases.routes.ts"
if [[ ! -f "$ROUTES_FILE" ]]; then
  echo "❌ Missing $ROUTES_FILE"
  exit 1
fi

if ! grep -q "/purchases/:purchaseId/refund" "$ROUTES_FILE"; then
  echo "== Patching $ROUTES_FILE (add refund endpoint) =="
  cp "$ROUTES_FILE" "scripts/.bak/purchases.routes.ts.bak.$(date +%Y%m%d_%H%M%S)"

  # Ensure import exists
  if ! grep -q "refundPropertyPurchase" "$ROUTES_FILE"; then
    perl -0777 -i -pe 's/import \{ payPropertyPurchase \} from "\.\.\/services\/purchase_payments\.service\.js";/import { payPropertyPurchase } from "..\/services\/purchase_payments.service.js";\nimport { refundPropertyPurchase } from "..\/services\/purchase_refunds.service.js";/g' "$ROUTES_FILE"
  fi

  # Insert route near the pay route (append at end of plugin function)
  perl -0777 -i -pe 's/(\n\}\s*\n\}\s*\n$)/\n  \/\/ ------------------------------------------------------------\n  \/\/ POST \/purchases\/:purchaseId\/refund\n  \/\/ ------------------------------------------------------------\n  fastify.post<{\n    Params: { purchaseId: string };\n    Body: { refundMethod: "card" | "bank_transfer" | "wallet"; amount?: number };\n  }>(\"\/purchases\/:purchaseId\/refund\", async (request, reply) => {\n    const orgId = String(request.headers[\"x-organization-id\"] || \"\");\n    if (!orgId) {\n      return reply.code(400).send({ ok: false, error: \"ORG_REQUIRED\", message: \"x-organization-id required\" });\n    }\n\n    const { purchaseId } = request.params;\n    const refundMethod = request.body?.refundMethod;\n    const amount = request.body?.amount;\n\n    if (!refundMethod) {\n      return reply.code(400).send({ ok: false, error: \"REFUND_METHOD_REQUIRED\", message: \"refundMethod is required\" });\n    }\n\n    const client = await fastify.pg.connect();\n    try {\n      const result = await refundPropertyPurchase(client, {\n        organizationId: orgId,\n        purchaseId,\n        refundMethod,\n        amount: typeof amount === \"number\" ? amount : undefined,\n      });\n      return reply.send({ ok: true, data: result });\n    } finally {\n      client.release();\n    }\n  });\n$1/s' "$ROUTES_FILE"

  echo "✅ Patched refund route into $ROUTES_FILE"
else
  echo "ℹ️ Refund route already present in purchases.routes.ts (skipping)"
fi

# -----------------------------
# 5) Verify purchasesRoutes is registered only ONCE in routes/index.ts
# -----------------------------
INDEX_FILE="src/routes/index.ts"
if [[ ! -f "$INDEX_FILE" ]]; then
  echo "❌ Missing $INDEX_FILE"
  exit 1
fi

# If purchasesRoutes appears multiple times, keep only the first registration
COUNT="$(grep -n "app.register(purchasesRoutes" "$INDEX_FILE" | wc -l | tr -d '[:space:]')"
if [[ "$COUNT" -gt 1 ]]; then
  echo "== Fixing duplicate purchasesRoutes registration in $INDEX_FILE (count=$COUNT) =="
  cp "$INDEX_FILE" "scripts/.bak/routes.index.ts.bak.$(date +%Y%m%d_%H%M%S)"
  # delete all but the first occurrence
  awk '
    /app\.register\(purchasesRoutes/ {
      seen++;
      if (seen>1) next;
    }
    { print }
  ' "$INDEX_FILE" > /tmp/index.ts.$$ && mv /tmp/index.ts.$$ "$INDEX_FILE"
  echo "✅ Deduped purchasesRoutes registration"
else
  echo "ℹ️ purchasesRoutes registration count ok ($COUNT)"
fi

echo ""
echo "✅ DONE: Refund flow added"
echo ""
echo "NEXT:"
echo "  1) Restart server: npm run dev"
echo "  2) Test refund endpoint:"
echo "     curl -sS -X POST \"\$API/v1/purchases/\$PURCHASE_ID/refund\" -H \"content-type: application/json\" -H \"authorization: Bearer \$TOKEN\" -H \"x-organization-id: \$ORG_ID\" -d '{\"refundMethod\":\"card\",\"amount\":2000}' | jq"
echo ""
echo "  3) Verify ledger reversal txns:"
echo "     PAGER=cat psql -d \"\$DB_NAME\" -X -c \"select wt.txn_type, wt.amount, wa.is_platform_wallet, wa.user_id, wt.reference_type, wt.created_at from public.wallet_transactions wt join public.wallet_accounts wa on wa.id=wt.wallet_account_id where wt.reference_id='\$PURCHASE_ID'::uuid and wt.reference_type in ('purchase','purchase_refund') order by wt.created_at asc;\""
echo ""
echo "  4) Verify purchase refund milestones:"
echo "     PAGER=cat psql -d \"\$DB_NAME\" -X -c \"select id, payment_status, refunded_at, refunded_amount from public.property_purchases where id='\$PURCHASE_ID'::uuid;\""
