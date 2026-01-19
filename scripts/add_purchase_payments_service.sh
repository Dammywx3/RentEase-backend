#!/usr/bin/env bash
set -eo pipefail

ROOT="$(pwd)"
echo "ROOT=$ROOT"

mkdir -p scripts/.bak src/services

ts_file="src/services/purchase_payments.service.ts"

# backup if file exists
if [ -f "$ts_file" ]; then
  ts="$(date +%Y%m%d_%H%M%S)"
  cp "$ts_file" "scripts/.bak/purchase_payments.service.ts.bak.$ts"
  echo "✅ backup -> scripts/.bak/purchase_payments.service.ts.bak.$ts"
fi

cat > "$ts_file" <<'TS'
import type { PoolClient } from "pg";
import { computePlatformFeeSplit } from "../config/fees.config.js";
import { creditPayee, creditPlatformFee } from "./ledger.service.js";

/**
 * Purchase payment service
 * Pattern matches rent invoice pay:
 *  - compute 2.5% platform fee
 *  - credit platform wallet (credit_platform_fee)
 *  - credit payee/seller wallet (credit_payee)
 *
 * NOTE:
 * - This assumes seller is properties.owner_id.
 * - For full purchase flow, you should also create property_purchases rows,
 *   accept escrow/deposit, and then call this function when payment is successful.
 */

export type PurchaseStatus =
  | "draft"
  | "agreement"
  | "escrow"
  | "paid"
  | "completed"
  | "cancelled";

export type PurchasePaymentMethod = "card" | "bank_transfer" | "wallet";

export type PropertyPurchaseRow = {
  id: string;
  organization_id: string;
  property_id: string;
  buyer_id: string;
  seller_id: string;
  agreed_price: string; // numeric(15,2) -> string
  currency: string | null;
  status: PurchaseStatus;
  escrow_amount: string | null;
  escrow_paid_at: string | null;
  closing_date: string | null;
  completed_at: string | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
};

async function resolveSellerUserId(
  client: PoolClient,
  args: { organizationId: string; propertyId: string }
): Promise<string> {
  const r = await client.query<{ seller_user_id: string }>(
    `
    SELECT p.owner_id AS seller_user_id
    FROM public.properties p
    WHERE p.id = $1::uuid
      AND p.organization_id = $2::uuid
      AND p.deleted_at IS NULL
    LIMIT 1;
    `,
    [args.propertyId, args.organizationId]
  );
  const seller = r.rows[0]?.seller_user_id;
  if (!seller) throw new Error("Cannot resolve seller_user_id for property " + args.propertyId);
  return seller;
}

/**
 * Create (or fetch) a purchase agreement row.
 * This is a minimal version: you can expand fields later.
 */
export async function createPropertyPurchase(
  client: PoolClient,
  args: {
    organizationId: string;
    propertyId: string;
    buyerId: string;
    agreedPrice: number;
    currency?: string | null;
  }
): Promise<PropertyPurchaseRow> {
  const sellerId = await resolveSellerUserId(client, {
    organizationId: args.organizationId,
    propertyId: args.propertyId,
  });

  const currency = (args.currency ?? "USD") || "USD";

  const { rows } = await client.query<PropertyPurchaseRow>(
    `
    INSERT INTO public.property_purchases (
      organization_id,
      property_id,
      buyer_id,
      seller_id,
      agreed_price,
      currency,
      status
    )
    VALUES (
      $1::uuid, $2::uuid, $3::uuid, $4::uuid, $5::numeric, $6::text, 'agreement'
    )
    RETURNING
      id,
      organization_id,
      property_id,
      buyer_id,
      seller_id,
      agreed_price::text AS agreed_price,
      currency,
      status,
      escrow_amount::text AS escrow_amount,
      escrow_paid_at::text AS escrow_paid_at,
      closing_date::text AS closing_date,
      completed_at::text AS completed_at,
      created_at::text AS created_at,
      updated_at::text AS updated_at,
      deleted_at::text AS deleted_at;
    `,
    [
      args.organizationId,
      args.propertyId,
      args.buyerId,
      sellerId,
      args.agreedPrice,
      currency,
    ]
  );

  if (!rows[0]) throw new Error("Failed to create property_purchases row");
  return rows[0];
}

/**
 * Mark purchase as paid and write wallet transactions:
 *  - platform fee (2.5%)
 *  - seller net
 *
 * Idempotency:
 *  - If purchase already 'paid' or 'completed', we won't double-credit.
 *  - We also use ON CONFLICT DO NOTHING on wallet txns (assuming unique constraints exist).
 */
export async function payPropertyPurchase(
  client: PoolClient,
  args: {
    organizationId: string;
    purchaseId: string;
    amount?: number | null; // defaults to agreed_price
    paymentMethod: PurchasePaymentMethod;
  }
): Promise<{ purchase: PropertyPurchaseRow; alreadyPaid: boolean; platformFee: number; sellerNet: number }> {
  const { rows: found } = await client.query<PropertyPurchaseRow>(
    `
    SELECT
      id,
      organization_id,
      property_id,
      buyer_id,
      seller_id,
      agreed_price::text AS agreed_price,
      currency,
      status,
      escrow_amount::text AS escrow_amount,
      escrow_paid_at::text AS escrow_paid_at,
      closing_date::text AS closing_date,
      completed_at::text AS completed_at,
      created_at::text AS created_at,
      updated_at::text AS updated_at,
      deleted_at::text AS deleted_at
    FROM public.property_purchases
    WHERE id = $1::uuid
      AND organization_id = $2::uuid
      AND deleted_at IS NULL
    LIMIT 1;
    `,
    [args.purchaseId, args.organizationId]
  );

  const purchase = found[0];
  if (!purchase) throw new Error("Purchase not found: " + args.purchaseId);

  if (purchase.status === "paid" || purchase.status === "completed") {
    return { purchase, alreadyPaid: true, platformFee: 0, sellerNet: 0 };
  }

  const currency = (purchase.currency ?? "USD") || "USD";
  const agreed = Number(purchase.agreed_price);
  const amount = typeof args.amount === "number" ? args.amount : agreed;

  if (Number(amount) !== Number(agreed)) {
    const e: any = new Error(`Payment.amount (${amount}) must equal agreed_price (${purchase.agreed_price})`);
    e.code = "AMOUNT_MISMATCH";
    throw e;
  }

  const split = computePlatformFeeSplit({
    paymentKind: "buy",
    amount,
    currency,
  });

  // 1) Credit platform fee
  await creditPlatformFee(client, {
    organizationId: args.organizationId,
    referenceType: "purchase",
    referenceId: purchase.id,
    amount: split.platformFee,
    currency,
    note: `2.5% platform fee for purchase ${purchase.id}`,
  });

  // 2) Credit seller net
  await creditPayee(client, {
    organizationId: args.organizationId,
    payeeUserId: purchase.seller_id,
    referenceType: "purchase",
    referenceId: purchase.id,
    amount: split.payeeNet,
    currency,
    note: `Purchase payout (net) for purchase ${purchase.id}`,
  });

  // 3) Mark paid
  const { rows: updated } = await client.query<PropertyPurchaseRow>(
    `
    UPDATE public.property_purchases
    SET
      status = 'paid',
      updated_at = NOW()
    WHERE id = $1::uuid
      AND organization_id = $2::uuid
      AND deleted_at IS NULL
    RETURNING
      id,
      organization_id,
      property_id,
      buyer_id,
      seller_id,
      agreed_price::text AS agreed_price,
      currency,
      status,
      escrow_amount::text AS escrow_amount,
      escrow_paid_at::text AS escrow_paid_at,
      closing_date::text AS closing_date,
      completed_at::text AS completed_at,
      created_at::text AS created_at,
      updated_at::text AS updated_at,
      deleted_at::text AS deleted_at;
    `,
    [purchase.id, args.organizationId]
  );

  return { purchase: updated[0]!, alreadyPaid: false, platformFee: split.platformFee, sellerNet: split.payeeNet };
}
TS

echo "✅ WROTE: $ts_file"

echo ""
echo "== OPTIONAL SQL: add purchase tables/enums if missing =="
echo "If you want, run:"
echo "  bash scripts/add_purchase_tables.sql.sh"
echo ""

# Write a helper script for SQL migration (user runs explicitly)
cat > scripts/add_purchase_tables.sql.sh <<'SQLBASH'
#!/usr/bin/env bash
set -eo pipefail
: "${DB_NAME:?DB_NAME not set}"

psql -d "$DB_NAME" <<'SQL'
BEGIN;

-- Minimal purchase status enum (safe if already exists)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'purchase_status') THEN
    CREATE TYPE purchase_status AS ENUM ('draft','agreement','escrow','paid','completed','cancelled');
  END IF;
END$$;

-- Purchase order / closing tracker
CREATE TABLE IF NOT EXISTS public.property_purchases (
  id uuid PRIMARY KEY DEFAULT rentease_uuid(),
  organization_id uuid NOT NULL DEFAULT current_organization_uuid() REFERENCES public.organizations(id),
  property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,

  buyer_id uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  seller_id uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,

  agreed_price numeric(15,2) NOT NULL,
  currency varchar(3) DEFAULT 'USD',

  status purchase_status NOT NULL DEFAULT 'agreement',

  escrow_amount numeric(15,2),
  escrow_paid_at timestamptz,

  closing_date date,
  completed_at timestamptz,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_property_purchases_org ON public.property_purchases(organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_property_purchases_property ON public.property_purchases(property_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_property_purchases_buyer ON public.property_purchases(buyer_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_property_purchases_seller ON public.property_purchases(seller_id, created_at DESC);

-- trigger updated_at (if your set_updated_at() exists)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname='set_updated_at') THEN
    BEGIN
      CREATE TRIGGER set_updated_at_property_purchases
      BEFORE UPDATE ON public.property_purchases
      FOR EACH ROW EXECUTE FUNCTION set_updated_at();
    EXCEPTION WHEN duplicate_object THEN
      -- ignore
      NULL;
    END;
  END IF;
END$$;

COMMIT;
SQL

echo "✅ purchase tables ready"
SQLBASH

chmod +x scripts/add_purchase_tables.sql.sh

echo "✅ WROTE: scripts/add_purchase_tables.sql.sh"
echo ""
echo "== DONE =="
echo "➡️ Next: import and use purchase_payments.service.ts from your route/controller."
