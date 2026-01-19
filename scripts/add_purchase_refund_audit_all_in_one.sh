#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DB_NAME="${DB_NAME:-rentease}"
SQL_DIR="$ROOT/scripts/sql"
SQL_FILE="$SQL_DIR/2026_01_16_purchase_refund_audit_fields.sql"

SVC="$ROOT/src/services/purchase_refunds.service.ts"
ROUTES="$ROOT/src/routes/purchases.routes.ts"

TS="$(date +%Y%m%d_%H%M%S)"
BAK="$ROOT/scripts/.bak"
mkdir -p "$BAK" "$SQL_DIR"

backup() {
  local f="$1"
  if [ -f "$f" ]; then
    cp "$f" "$BAK/$(basename "$f").bak.$TS"
    echo "backup: $f -> $BAK/$(basename "$f").bak.$TS"
  fi
}

echo "==> backups"
backup "$SVC"
backup "$ROUTES"

echo "==> writing SQL: $SQL_FILE"
cat > "$SQL_FILE" <<'SQL'
BEGIN;

-- Add refund audit fields to purchases (safe if already exists)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='property_purchases' AND column_name='refund_method'
  ) THEN
    ALTER TABLE public.property_purchases ADD COLUMN refund_method text;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='property_purchases' AND column_name='refunded_reason'
  ) THEN
    ALTER TABLE public.property_purchases ADD COLUMN refunded_reason text;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='property_purchases' AND column_name='refunded_by'
  ) THEN
    ALTER TABLE public.property_purchases ADD COLUMN refunded_by uuid;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='property_purchases' AND column_name='refund_payment_id'
  ) THEN
    ALTER TABLE public.property_purchases ADD COLUMN refund_payment_id uuid;
  END IF;
END $$;

-- Indexes (only if missing)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='public' AND indexname='idx_property_purchases_refunded_by'
  ) THEN
    CREATE INDEX idx_property_purchases_refunded_by
      ON public.property_purchases(refunded_by, refunded_at DESC)
      WHERE refunded_by IS NOT NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='public' AND indexname='idx_property_purchases_refund_payment_id'
  ) THEN
    CREATE INDEX idx_property_purchases_refund_payment_id
      ON public.property_purchases(refund_payment_id)
      WHERE refund_payment_id IS NOT NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='public' AND indexname='idx_property_purchases_refund_method'
  ) THEN
    CREATE INDEX idx_property_purchases_refund_method
      ON public.property_purchases(refund_method, refunded_at DESC)
      WHERE refund_method IS NOT NULL;
  END IF;
END $$;

-- Foreign keys (safe add-if-missing via pg_constraint checks)
DO $$
BEGIN
  -- refunded_by -> users.id
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname='property_purchases_refunded_by_fkey'
  ) THEN
    ALTER TABLE public.property_purchases
      ADD CONSTRAINT property_purchases_refunded_by_fkey
      FOREIGN KEY (refunded_by) REFERENCES public.users(id)
      ON DELETE SET NULL;
  END IF;

  -- refund_payment_id -> payments.id
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname='property_purchases_refund_payment_id_fkey'
  ) THEN
    ALTER TABLE public.property_purchases
      ADD CONSTRAINT property_purchases_refund_payment_id_fkey
      FOREIGN KEY (refund_payment_id) REFERENCES public.payments(id)
      ON DELETE SET NULL;
  END IF;
END $$;

COMMIT;
SQL

echo "==> applying SQL to DB=$DB_NAME"
psql -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$SQL_FILE"

# -------------------------------
# Patch purchase_refunds.service.ts
# -------------------------------
if [ ! -f "$SVC" ]; then
  echo "❌ Not found: $SVC"
  exit 1
fi

echo "==> patching service: $SVC"

# 1) Extend PropertyPurchaseRow + PURCHASE_SELECT (insert fields if missing)
# Add types
perl -0777 -i -pe '
  if ($ARGV =~ /purchase_refunds\.service\.ts$/) {
    # Add fields to PropertyPurchaseRow (after refunded_amount)
    if ($_.!~/refund_method:\s*string\s*\|\s*null;/) {
      s/(refunded_amount:\s*string\s*\|\s*null;\s*\n\};)/refunded_amount: string | null;\n\n  refund_method: string | null;\n  refunded_reason: string | null;\n  refunded_by: string | null;\n  refund_payment_id: string | null;\n};/s;
    }

    # Add fields to PURCHASE_SELECT (after refunded_amount)
    if ($_.!~/pp\.refund_method::text\s+AS\s+refund_method/) {
      s/(pp\.refunded_amount::text\s+AS\s+refunded_amount\s*\n`;\s*)/pp.refunded_amount::text AS refunded_amount,\n\n  pp.refund_method::text AS refund_method,\n  pp.refunded_reason::text AS refunded_reason,\n  pp.refunded_by::text AS refunded_by,\n  pp.refund_payment_id::text AS refund_payment_id\n`;\n/s;
    }
  }
' "$SVC"

# 2) Ensure refundPropertyPurchase args include refundPaymentId + refundedByUserId
perl -0777 -i -pe '
  if ($ARGV =~ /purchase_refunds\.service\.ts$/) {
    # Add args fields if missing
    if ($_.!~/refundPaymentId\?:\s*string\s*\|\s*null/) {
      s/(refundMethod\?:\s*RefundMethod;\s*\/\/ accepted for API symmetry; not used in DB logic\s*)/refundMethod?: RefundMethod; \/\/ accepted for API symmetry; stored as audit\n    refundPaymentId?: string | null; \/\/ optional audit link (payments.id)\n    refundedByUserId?: string | null; \/\/ optional audit (users.id)\n/s;
    } else {
      # If exists but old comment, leave.
    }
  }
' "$SVC"

# 3) Update upsertRefundMilestones to set audit fields (COALESCE so idempotent)
# Replace the UPDATE block inside upsertRefundMilestones if it doesn't include refund_method
perl -0777 -i -pe '
  if ($ARGV =~ /purchase_refunds\.service\.ts$/) {
    if ($_.!~/refund_method\s*=\s*COALESCE/) {
      s/async function upsertRefundMilestones\([\s\S]*?\)\s*\{\s*await client\.query\(\s*`\s*UPDATE public\.property_purchases[\s\S]*?WHERE id = \$2::uuid[\s\S]*?`[\s\S]*?\);\s*\}/async function upsertRefundMilestones(\n  client: PoolClient,\n  args: {\n    organizationId: string;\n    purchaseId: string;\n    amount: number;\n    refundMethod: RefundMethod | null;\n    reason: string | null;\n    refundedByUserId: string | null;\n    refundPaymentId: string | null;\n  }\n) {\n  await client.query(\n    `\n    UPDATE public.property_purchases\n    SET\n      payment_status = \x27refunded\x27::purchase_payment_status,\n      refunded_at = COALESCE(refunded_at, NOW()),\n      refunded_amount = COALESCE(refunded_amount, 0) + $1::numeric,\n\n      refund_method = COALESCE(refund_method, $4),\n      refunded_reason = COALESCE(refunded_reason, $5),\n      refunded_by = COALESCE(refunded_by, NULLIF($6, \x27\x27)::uuid),\n      refund_payment_id = COALESCE(refund_payment_id, NULLIF($7, \x27\x27)::uuid),\n\n      updated_at = NOW()\n    WHERE id = $2::uuid\n      AND organization_id = $3::uuid\n      AND deleted_at IS NULL;\n    `,\n    [\n      args.amount,\n      args.purchaseId,\n      args.organizationId,\n      args.refundMethod,\n      args.reason,\n      args.refundedByUserId,\n      args.refundPaymentId,\n    ]\n  );\n}/s;
    }
  }
' "$SVC"

# 4) Ensure calls to upsertRefundMilestones pass audit args
perl -0777 -i -pe '
  if ($ARGV =~ /purchase_refunds\.service\.ts$/) {

    # In the idempotent branch: upsertRefundMilestones(...) should pass refundMethod/reason/user/payment
    s/upsertRefundMilestones\(client,\s*\{\s*organizationId:\s*args\.organizationId,\s*purchaseId:\s*purchase\.id,\s*amount,\s*lastPaymentId:\s*purchase\.last_payment_id\s*\?\?\s*null,\s*\}\);/upsertRefundMilestones(client, {\n      organizationId: args.organizationId,\n      purchaseId: purchase.id,\n      amount,\n      refundMethod: args.refundMethod ?? null,\n      reason: args.reason ?? null,\n      refundedByUserId: args.refundedByUserId ?? null,\n      refundPaymentId: args.refundPaymentId ?? null,\n    });/s;

    # In the normal branch: upsertRefundMilestones(...) also
    s/upsertRefundMilestones\(client,\s*\{\s*organizationId:\s*args\.organizationId,\s*purchaseId:\s*purchase\.id,\s*amount,\s*lastPaymentId:\s*purchase\.last_payment_id\s*\?\?\s*null,\s*\}\);/upsertRefundMilestones(client, {\n    organizationId: args.organizationId,\n    purchaseId: purchase.id,\n    amount,\n    refundMethod: args.refundMethod ?? null,\n    reason: args.reason ?? null,\n    refundedByUserId: args.refundedByUserId ?? null,\n    refundPaymentId: args.refundPaymentId ?? null,\n  });/s;

  }
' "$SVC"

# -------------------------------
# Patch purchases.routes.ts refund route to accept + pass audit fields
# -------------------------------
if [ ! -f "$ROUTES" ]; then
  echo "❌ Not found: $ROUTES"
  exit 1
fi

echo "==> patching routes: $ROUTES"

# 1) Expand refund Body type to include reason + refundPaymentId (if your file uses typed route)
perl -0777 -i -pe '
  if ($ARGV =~ /purchases\.routes\.ts$/) {
    # Expand Body type for refund route
    s/Body:\s*\{\s*refundMethod:\s*"card"\s*\|\s*"bank_transfer"\s*\|\s*"wallet";\s*amount\?:\s*number;\s*\};/Body: { refundMethod: "card" | "bank_transfer" | "wallet"; amount?: number; reason?: string; refundPaymentId?: string };/s;

    # If the above pattern didnt match (file might differ), do a softer insert:
    if ($_.!~/refundPaymentId\?:\s*string/ && /refundMethod:\s*"card"\s*\|\s*"bank_transfer"\s*\|\s*"wallet"/) {
      s/(refundMethod:\s*"card"\s*\|\s*"bank_transfer"\s*\|\s*"wallet";\s*amount\?:\s*number;)/$1 reason?: string; refundPaymentId?: string;/s;
    }
  }
' "$ROUTES"

# 2) In the refund handler: read reason/refundPaymentId, and pass refundedByUserId
perl -0777 -i -pe '
  if ($ARGV =~ /purchases\.routes\.ts$/) {

    # Add extraction lines after refundMethod line if missing
    if ($_.!~/const reason = request\.body\?\.reason/) {
      s/(const refundMethod = request\.body\?\.refundMethod;)/$1\n\n    const reason = (request.body as any)?.reason ?? null;\n    const refundPaymentId = (request.body as any)?.refundPaymentId ?? null;\n    const refundedByUserId = (request as any).user?.sub ?? (request as any).user?.id ?? null;/s;
    }

    # When calling refundPropertyPurchase(...), add audit args if missing
    if ($_.!~/refundPaymentId:/) {
      s/(refundPropertyPurchase\(client,\s*\{\s*organizationId:\s*orgId,\s*purchaseId,\s*amount,\s*reason\s*\}\))/refundPropertyPurchase(client, {\n        organizationId: orgId,\n        purchaseId,\n        amount,\n        reason,\n        refundMethod,\n        refundPaymentId,\n        refundedByUserId,\n      })/s;
    }

  }
' "$ROUTES"

# sanity checks
grep -q "refundPaymentId" "$SVC" || { echo "❌ service patch sanity check failed (refundPaymentId missing)"; exit 1; }
grep -q "refunded_by" "$SQL_FILE" || { echo "❌ sql patch sanity check failed (refunded_by missing)"; exit 1; }

echo ""
echo "==> typecheck"
npx -y tsc -p "$ROOT/tsconfig.json" --noEmit

echo ""
echo "✅ DONE"
echo "NEXT:"
echo "  1) restart server: npm run dev"
echo "  2) test refund with audit:"
echo "     curl -sS -X POST \"\$API/v1/purchases/\$PURCHASE_ID/refund\" \\"
echo "       -H \"content-type: application/json\" \\"
echo "       -H \"authorization: Bearer \$TOKEN\" \\"
echo "       -H \"x-organization-id: \$ORG_ID\" \\"
echo "       -d '{\"refundMethod\":\"card\",\"amount\":2000,\"reason\":\"buyer cancelled\",\"refundPaymentId\":\"21c4d5c8-94b5-4330-b34e-96173d2e4684\"}' | jq"
