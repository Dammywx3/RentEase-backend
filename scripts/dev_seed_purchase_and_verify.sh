#!/usr/bin/env bash
set -euo pipefail

: "${DB_NAME:?DB_NAME not set}"

echo "DB_NAME=$DB_NAME"

# Pick a listing+property (must exist because payments.listing_id is NOT NULL)
LISTING_ID="$(psql -d "$DB_NAME" -Atc "
  select id
  from public.property_listings
  where deleted_at is null
  order by created_at desc
  limit 1;
")"

if [[ -z "${LISTING_ID}" ]]; then
  echo "❌ No property_listings found. Create a listing first, then re-run."
  exit 1
fi

PROPERTY_ID="$(psql -d "$DB_NAME" -Atc "
  select property_id
  from public.property_listings
  where id='${LISTING_ID}'::uuid
  limit 1;
")"

if [[ -z "${PROPERTY_ID}" ]]; then
  echo "❌ Could not resolve property_id from listing ${LISTING_ID}"
  exit 1
fi

# Buyer/Seller (pick 2 different users; if only 1 user exists, abort)
BUYER_ID="$(psql -d "$DB_NAME" -Atc "
  select id from public.users
  where deleted_at is null
  order by created_at desc
  limit 1;
")"

SELLER_ID="$(psql -d "$DB_NAME" -Atc "
  select id from public.users
  where deleted_at is null
    and id <> '${BUYER_ID}'::uuid
  order by created_at desc
  limit 1;
")"

if [[ -z "${BUYER_ID}" || -z "${SELLER_ID}" ]]; then
  echo "❌ Need at least TWO users to create buyer/seller. Create another user then re-run."
  exit 1
fi

ORG_ID="$(psql -d "$DB_NAME" -Atc "
  select organization_id
  from public.property_listings
  where id='${LISTING_ID}'::uuid
  limit 1;
")"

if [[ -z "${ORG_ID}" ]]; then
  # fallback: take current_organization_uuid if your session supports it, else pick latest org
  ORG_ID="$(psql -d "$DB_NAME" -Atc "select id from public.organizations order by created_at desc limit 1;")"
fi

if [[ -z "${ORG_ID}" ]]; then
  echo "❌ Could not determine organization_id (no orgs found)."
  exit 1
fi

AGREED_PRICE="2000.00"
CURRENCY="USD"

echo "Using:"
echo "  ORG_ID=$ORG_ID"
echo "  LISTING_ID=$LISTING_ID"
echo "  PROPERTY_ID=$PROPERTY_ID"
echo "  BUYER_ID=$BUYER_ID"
echo "  SELLER_ID=$SELLER_ID"
echo "  AGREED_PRICE=$AGREED_PRICE $CURRENCY"

# 1) Insert purchase
PURCHASE_ID="$(psql -d "$DB_NAME" -Atc "
  insert into public.property_purchases (
    organization_id, buyer_id, seller_id, property_id, listing_id,
    agreed_price, currency, status, notes
  )
  values (
    '${ORG_ID}'::uuid,
    '${BUYER_ID}'::uuid,
    '${SELLER_ID}'::uuid,
    '${PROPERTY_ID}'::uuid,
    '${LISTING_ID}'::uuid,
    ${AGREED_PRICE}::numeric,
    '${CURRENCY}',
    'under_contract'::purchase_status,
    'dev seed purchase'
  )
  returning id;
")"

echo "✅ PURCHASE_ID=$PURCHASE_ID"

# 2) Insert a successful payment row for the buyer (tenant_id column is used as payer)
TX_REF="DEV-PURCHASE-$(date +%s)"

PAYMENT_ID="$(psql -d "$DB_NAME" -Atc "
  insert into public.payments (
    tenant_id, listing_id, property_id, amount, currency,
    status, transaction_reference, payment_method,
    reference_type, reference_id,
    initiated_at, completed_at
  )
  values (
    '${BUYER_ID}'::uuid,
    '${LISTING_ID}'::uuid,
    '${PROPERTY_ID}'::uuid,
    ${AGREED_PRICE}::numeric,
    '${CURRENCY}',
    'successful'::payment_status,
    '${TX_REF}',
    'card'::payment_method,
    'purchase',
    '${PURCHASE_ID}'::uuid,
    now(),
    now()
  )
  returning id;
")"

echo "✅ PAYMENT_ID=$PAYMENT_ID"

# 3) Link payment to purchase
psql -d "$DB_NAME" -v ON_ERROR_STOP=1 -c "
insert into public.property_purchase_payments (organization_id, purchase_id, payment_id, amount)
values ('${ORG_ID}'::uuid, '${PURCHASE_ID}'::uuid, '${PAYMENT_ID}'::uuid, ${AGREED_PRICE}::numeric)
on conflict do nothing;
"

echo "✅ Linked payment -> purchase"

# 4) NOW you must call your Node service (payPropertyPurchase) from your route/controller
# If you haven't wired a route yet, we can still validate the DB side is ready.
# For ledger verification, you need to actually run the service that inserts wallet_transactions.

echo ""
echo "== NEXT STEP REQUIRED =="
echo "You still need to RUN your purchase payment flow (service) to create wallet_transactions:"
echo "  payPropertyPurchase(...) must execute to insert:"
echo "   - credit_platform_fee"
echo "   - credit_payee"
echo ""
echo "For now, here is the purchase id you will use:"
echo "  export PURCHASE_ID=${PURCHASE_ID}"
echo ""
echo "When you run the service, verify with:"
echo "PAGER=cat psql -d \"$DB_NAME\" -c \""
echo "select wt.txn_type, wt.amount, wa.is_platform_wallet, wa.user_id"
echo "from public.wallet_transactions wt"
echo "join public.wallet_accounts wa on wa.id = wt.wallet_account_id"
echo "where wt.reference_type='purchase'"
echo "  and wt.reference_id='${PURCHASE_ID}'::uuid"
echo "order by wt.created_at asc;\""
