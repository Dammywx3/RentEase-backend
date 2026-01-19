#!/usr/bin/env bash
set -euo pipefail

DB="${DB:-rentease}"
PAYMENT_ID="${1:-b77e1471-ef74-43fe-baf7-1accd5717679}"

echo "== Run payment success with org context + ensure wallets =="
echo "DB: $DB"
echo "PAYMENT_ID: $PAYMENT_ID"
echo ""

psql -d "$DB" -X -v ON_ERROR_STOP=1 <<SQL
\\set ON_ERROR_STOP on

-- 1) Infer org_id from the payment reference (purchase or rent_invoice)
WITH p AS (
  SELECT id, reference_type, reference_id, currency
  FROM public.payments
  WHERE id = '$PAYMENT_ID'::uuid
  LIMIT 1
),
org AS (
  SELECT
    CASE
      WHEN p.reference_type = 'purchase' THEN pp.organization_id
      WHEN p.reference_type = 'rent_invoice' THEN ri.organization_id
      ELSE NULL
    END AS organization_id,
    p.currency
  FROM p
  LEFT JOIN public.property_purchases pp
    ON p.reference_type = 'purchase' AND pp.id = p.reference_id
  LEFT JOIN public.rent_invoices ri
    ON p.reference_type = 'rent_invoice' AND ri.id = p.reference_id
)
SELECT
  CASE
    WHEN organization_id IS NULL THEN
      (SELECT current_organization_uuid())
    ELSE organization_id
  END AS organization_id,
  currency
INTO TEMP TABLE __ctx
FROM org;

-- 2) Fail fast if still null
DO \$\$
DECLARE v_org uuid;
BEGIN
  SELECT organization_id INTO v_org FROM __ctx LIMIT 1;
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'Cannot infer organization_id for payment %. Ensure purchase/rent_invoice has organization_id OR set app.organization_id manually.', '$PAYMENT_ID';
  END IF;
END
\$\$;

-- 3) Set session org for triggers/functions
SELECT set_config('app.organization_id', (SELECT organization_id::text FROM __ctx LIMIT 1), true) AS app_org_set;

-- 4) Ensure platform wallet exists (uses is_platform_wallet=true)
INSERT INTO public.wallet_accounts (id, organization_id, user_id, currency, is_platform_wallet, purpose, created_at, updated_at)
SELECT
  gen_random_uuid(),
  (SELECT organization_id FROM __ctx LIMIT 1),
  NULL,
  COALESCE((SELECT currency FROM __ctx LIMIT 1), 'USD'),
  true,
  'platform'::public.wallet_account_purpose,
  NOW(), NOW()
WHERE NOT EXISTS (
  SELECT 1
  FROM public.wallet_accounts wa
  WHERE wa.organization_id = (SELECT organization_id FROM __ctx LIMIT 1)
    AND COALESCE(wa.is_platform_wallet,false) = true
);

-- 5) Ensure payee wallet exists (user wallet for the payee split beneficiary_user_id)
-- We’ll create it only if splits already exist; if not, ensure_payment_splits will create splits first.
SELECT public.ensure_payment_splits('$PAYMENT_ID'::uuid);

INSERT INTO public.wallet_accounts (id, organization_id, user_id, currency, is_platform_wallet, purpose, created_at, updated_at)
SELECT
  gen_random_uuid(),
  (SELECT organization_id FROM __ctx LIMIT 1),
  ps.beneficiary_user_id,
  COALESCE(ps.currency, (SELECT currency FROM __ctx LIMIT 1), 'USD'),
  false,
  'user'::public.wallet_account_purpose,
  NOW(), NOW()
FROM public.payment_splits ps
WHERE ps.payment_id = '$PAYMENT_ID'::uuid
  AND ps.beneficiary_kind::text = 'user'
  AND ps.beneficiary_user_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.wallet_accounts wa
    WHERE wa.organization_id = (SELECT organization_id FROM __ctx LIMIT 1)
      AND wa.user_id = ps.beneficiary_user_id
  );

-- 6) Show context + wallets that will be used
\\echo ''
\\echo '--- Context + wallets ---'
SELECT (SELECT organization_id FROM __ctx LIMIT 1) AS organization_id;
SELECT id, organization_id, user_id, currency, is_platform_wallet, purpose
FROM public.wallet_accounts
WHERE organization_id = (SELECT organization_id FROM __ctx LIMIT 1)
ORDER BY is_platform_wallet DESC, created_at ASC;

\\echo ''
\\echo '--- Splits for payment ---'
SELECT split_type::text, beneficiary_kind::text, beneficiary_user_id, amount, currency
FROM public.payment_splits
WHERE payment_id = '$PAYMENT_ID'::uuid
ORDER BY created_at ASC;

-- 7) Trigger credits
\\echo ''
\\echo '--- Update payment -> successful (triggers credits) ---'
UPDATE public.payments
SET status = 'successful'::public.payment_status
WHERE id = '$PAYMENT_ID'::uuid;

\\echo ''
\\echo '--- Credits written (reference_type=payment) ---'
SELECT txn_type::text, amount, currency, reference_type, reference_id, created_at
FROM public.wallet_transactions
WHERE reference_type='payment'
  AND reference_id = '$PAYMENT_ID'::uuid
ORDER BY created_at DESC
LIMIT 50;
SQL

echo ""
echo "✅ Done."
