#!/usr/bin/env bash
set -euo pipefail

DB="${DB:-rentease}"

# Optional: keep terminal open when double-clicking / running from GUI
if [[ "${PAUSE_ON_EXIT:-0}" == "1" ]]; then
  trap 'code=$?; echo ""; echo "❌ Script stopped (exit code=$code). Press ENTER to close..."; read -r _; exit $code' EXIT
fi

CURRENCY="${CURRENCY:-NGN}"
AMOUNT="${AMOUNT:-2000.00}"
PLATFORM_FEE="${PLATFORM_FEE:-50.00}"
PAYEE_NET="${PAYEE_NET:-1950.00}"

# Optional arg: ./scripts/test_purchase_payment_e2e.sh <PURCHASE_ID>
PURCHASE_ID="${1:-${PURCHASE_ID:-}}"

psql_do() {
  psql -d "$DB" -X -v ON_ERROR_STOP=1 -P pager=off "$@"
}

psql_val() {
  # -tAq: tuples only, unaligned, quiet (prevents BEGIN/INSERT noise)
  psql -d "$DB" -X -v ON_ERROR_STOP=1 -P pager=off -tAq "$@"
}

trim() {
  awk '{$1=$1}1' <<< "${1:-}" | tr -d '\r' | tr -d '\n'
}

uuid_ok() {
  local v
  v="$(trim "${1:-}")"
  [[ "$v" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

need_uuid() {
  local name="$1" val="$2"
  if ! uuid_ok "$val"; then
    echo ""
    echo "❌ $name must be a UUID. Got: '$(printf "%s" "$val")'"
    echo ""
    exit 1
  fi
}

echo "== Purchase Payment E2E (payments table) =="
echo "DB: $DB"
echo "CURRENCY: $CURRENCY  AMOUNT: $AMOUNT  PLATFORM_FEE: $PLATFORM_FEE  PAYEE_NET: $PAYEE_NET"
echo ""

# ---------------------------
# 0) Resolve ORG_ID (must exist)
# ---------------------------
ORG_ID="$(trim "${ORG_ID:-}")"
if [[ -z "$ORG_ID" ]]; then
  ORG_ID="$(psql_val -c "select id::text from public.organizations order by created_at asc limit 1;")"
  ORG_ID="$(trim "$ORG_ID")"
fi
need_uuid "ORG_ID" "$ORG_ID"

# ---------------------------
# 1) Resolve LISTING_ID first (then derive PROPERTY_ID)
# payments.listing_id is NOT NULL, so LISTING_ID must exist.
# ---------------------------
LISTING_ID="$(trim "${LISTING_ID:-}")"
PROPERTY_ID="$(trim "${PROPERTY_ID:-}")"

if [[ -n "$LISTING_ID" ]]; then
  need_uuid "LISTING_ID" "$LISTING_ID"
  # derive property from listing
  PROPERTY_ID="$(psql_val -c "
    select pl.property_id::text
    from public.property_listings pl
    where pl.id = '$LISTING_ID'::uuid
      and pl.deleted_at is null
    limit 1;
  ")"
  PROPERTY_ID="$(trim "$PROPERTY_ID")"
  if [[ -z "$PROPERTY_ID" ]]; then
    echo ""
    echo "❌ LISTING_ID=$LISTING_ID not found or deleted."
    echo ""
    exit 1
  fi
  need_uuid "PROPERTY_ID" "$PROPERTY_ID"
else
  # If no LISTING_ID provided, pick one from the org (via property join)
  # If your listings table doesn't have organization_id, we join to properties to enforce org.
  read -r LISTING_ID PROPERTY_ID < <(
    psql_val -F '|' -c "
      select pl.id::text, pl.property_id::text
      from public.property_listings pl
      join public.properties pr
        on pr.id = pl.property_id
       and pr.deleted_at is null
      where pl.deleted_at is null
        and pr.organization_id = '$ORG_ID'::uuid
      order by pl.created_at asc
      limit 1;
    " | awk -F'|' '{print $1, $2}'
  )
  LISTING_ID="$(trim "$LISTING_ID")"
  PROPERTY_ID="$(trim "$PROPERTY_ID")"

  if [[ -z "$LISTING_ID" || -z "$PROPERTY_ID" ]]; then
    echo ""
    echo "❌ Could not find any property_listings for ORG_ID=$ORG_ID."
    echo "Your payments table requires listing_id NOT NULL."
    echo ""
    echo "Check:"
    echo "  psql -d $DB -X -P pager=off -c \"select pl.id, pl.property_id from public.property_listings pl where pl.deleted_at is null limit 20;\""
    echo ""
    exit 1
  fi

  need_uuid "LISTING_ID" "$LISTING_ID"
  need_uuid "PROPERTY_ID" "$PROPERTY_ID"
fi

# ---------------------------
# 2) Resolve BUYER_ID + SELLER_ID
# ---------------------------
BUYER_ID="$(trim "${BUYER_ID:-}")"
SELLER_ID="$(trim "${SELLER_ID:-}")"

if [[ -z "$BUYER_ID" ]]; then
  BUYER_ID="$(psql_val -c "select id::text from public.users order by created_at asc limit 1;")"
  BUYER_ID="$(trim "$BUYER_ID")"
fi
need_uuid "BUYER_ID" "$BUYER_ID"

if [[ -z "$SELLER_ID" ]]; then
  SELLER_ID="$(psql_val -c "
    select id::text
    from public.users
    where id <> '$BUYER_ID'::uuid
    order by created_at asc
    limit 1;
  ")"
  SELLER_ID="$(trim "$SELLER_ID")"
fi
need_uuid "SELLER_ID" "$SELLER_ID"

echo "Using:"
echo "  ORG_ID=$ORG_ID"
echo "  LISTING_ID=$LISTING_ID"
echo "  PROPERTY_ID=$PROPERTY_ID"
echo "  BUYER_ID=$BUYER_ID"
echo "  SELLER_ID=$SELLER_ID"
echo ""

# ---------------------------
# 3) Purchase: reuse existing open purchase for property/org, else create
# ---------------------------
if [[ -z "$PURCHASE_ID" ]]; then
  EXISTING_PURCHASE_ID="$(psql_val -c "
    select pp.id::text
    from public.property_purchases pp
    where pp.organization_id = '$ORG_ID'::uuid
      and pp.property_id = '$PROPERTY_ID'::uuid
      and pp.deleted_at is null
      and pp.status <> all (array[
        'closed'::public.purchase_status,
        'cancelled'::public.purchase_status,
        'refunded'::public.purchase_status
      ])
    order by pp.created_at desc
    limit 1;
  ")"
  EXISTING_PURCHASE_ID="$(trim "$EXISTING_PURCHASE_ID")"

  if [[ -n "$EXISTING_PURCHASE_ID" ]]; then
    PURCHASE_ID="$EXISTING_PURCHASE_ID"
    echo "-> Using existing open PURCHASE_ID: $PURCHASE_ID"
  else
    echo "-> Creating a new purchase..."
    PURCHASE_ID="$(psql_val -c "
      insert into public.property_purchases(
        organization_id, buyer_id, seller_id, property_id, listing_id,
        agreed_price, currency, status, payment_status
      )
      values (
        '$ORG_ID'::uuid,
        '$BUYER_ID'::uuid,
        '$SELLER_ID'::uuid,
        '$PROPERTY_ID'::uuid,
        '$LISTING_ID'::uuid,
        $AMOUNT::numeric(15,2),
        '$CURRENCY'::varchar(3),
        'initiated'::public.purchase_status,
        'unpaid'::public.purchase_payment_status
      )
      returning id::text;
    ")"
    PURCHASE_ID="$(trim "$PURCHASE_ID")"
    echo "✅ Created PURCHASE_ID: $PURCHASE_ID"
  fi
else
  PURCHASE_ID="$(trim "$PURCHASE_ID")"
  echo "-> Using provided PURCHASE_ID: $PURCHASE_ID"
fi

need_uuid "PURCHASE_ID" "$PURCHASE_ID"
echo ""

# ---------------------------
# 4) Create payment row referencing purchase + link table row
# ---------------------------
echo "-> Creating payment row referencing purchase + linking row in property_purchase_payments..."

PAYMENT_REF="test-purchase-e2e-$(psql_val -c "select gen_random_uuid()::text;")"
PAYMENT_REF="$(trim "$PAYMENT_REF")"

ROW="$(psql_val -F '|' -c "
with p as (
  select
    pp.id as purchase_id,
    pp.organization_id,
    pp.buyer_id,
    pp.seller_id,
    pp.property_id,
    coalesce(pp.listing_id, '$LISTING_ID'::uuid) as listing_id,
    coalesce(pp.currency, '$CURRENCY')::varchar(3) as currency
  from public.property_purchases pp
  where pp.id = '$PURCHASE_ID'::uuid
    and pp.deleted_at is null
  limit 1
),
ins_pay as (
  insert into public.payments(
    tenant_id,
    listing_id,
    property_id,
    amount,
    currency,
    status,
    transaction_reference,
    payment_method,
    reference_type,
    reference_id,
    platform_fee_amount,
    payee_amount
  )
  select
    p.buyer_id,
    p.listing_id,
    p.property_id,
    $AMOUNT::numeric(15,2),
    p.currency,
    'pending'::public.payment_status,
    '$PAYMENT_REF'::varchar(100),
    'card'::public.payment_method,
    'purchase'::text,
    p.purchase_id,
    $PLATFORM_FEE::numeric(15,2),
    $PAYEE_NET::numeric(15,2)
  from p
  returning id::text as payment_id, transaction_reference::text as tx_ref
),
ins_link as (
  insert into public.property_purchase_payments(
    organization_id, purchase_id, payment_id, amount
  )
  select
    (select organization_id from p),
    (select purchase_id from p),
    (select payment_id::uuid from ins_pay),
    $AMOUNT::numeric(15,2)
  on conflict do nothing
  returning 1
)
select payment_id || '|' || tx_ref from ins_pay;
")"

ROW="$(trim "$ROW")"
PAYMENT_ID="$(trim "${ROW%%|*}")"
TRANSACTION_REFERENCE="$(trim "${ROW#*|}")"

need_uuid "PAYMENT_ID" "$PAYMENT_ID"

echo "✅ PAYMENT_ID: $PAYMENT_ID"
echo "✅ transaction_reference: $TRANSACTION_REFERENCE"
echo ""

# ---------------------------
# 5) Validate + trigger credits
# ---------------------------
echo "-> 1) Show payment row:"
psql_do -c "
select id, status, amount, currency, reference_type, reference_id, platform_fee_amount, payee_amount, listing_id, property_id
from public.payments
where id='$PAYMENT_ID'::uuid;
"

echo "-> 2) Ensure splits:"
psql_do -c "select public.ensure_payment_splits('$PAYMENT_ID'::uuid);"

echo "-> 3) Show splits:"
psql_do -c "
select split_type::text, beneficiary_kind::text, beneficiary_user_id, amount, currency
from public.payment_splits
where payment_id='$PAYMENT_ID'::uuid
order by created_at asc;
"

echo "-> 4) Flip payment to successful (fires trigger -> wallet_credit_from_splits):"
psql_do -c "
update public.payments
set status='successful'::public.payment_status,
    completed_at=now()
where id='$PAYMENT_ID'::uuid;
"

echo "-> 5) Show credits written for this payment:"
psql_do -c "
select wt.txn_type::text, wt.amount, wt.currency, wt.reference_type, wt.reference_id, wt.created_at,
       wa.is_platform_wallet, wa.user_id
from public.wallet_transactions wt
join public.wallet_accounts wa on wa.id = wt.wallet_account_id
where wt.reference_type='payment'
  and wt.reference_id='$PAYMENT_ID'::uuid
order by wt.created_at desc
limit 50;
"

echo "-> 6) Confirm no duplicates:"
psql_do -c "
select reference_id, txn_type::text, currency, amount, count(*)
from public.wallet_transactions
where reference_type='payment'
  and reference_id='$PAYMENT_ID'::uuid
group by 1,2,3,4
having count(*) > 1;
"

echo ""
echo "✅ DONE. Purchase payment flow via payments table is working."
echo "Purchase: $PURCHASE_ID"
echo "Payment:  $PAYMENT_ID"
echo "Ref:      $TRANSACTION_REFERENCE"