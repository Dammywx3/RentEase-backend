#!/usr/bin/env bash
set -euo pipefail

DB="${DB:-rentease}"

echo "== Patch find_wallet_account_id(): handle wallet_accounts without deleted_at =="
echo "DB: $DB"
echo ""

psql -d "$DB" -X -v ON_ERROR_STOP=1 <<'SQL'
CREATE OR REPLACE FUNCTION public.find_wallet_account_id(
  p_org uuid,
  p_beneficiary_kind text,
  p_user_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
AS $function$
DECLARE
  v_id uuid;

  -- detected column names (if they exist)
  col_owner_kind text := NULL;
  col_user_id text := NULL;
  has_deleted_at boolean := false;

  q text;
  del_filter text := '';
BEGIN
  -- detect deleted_at
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public'
      AND table_name='wallet_accounts'
      AND column_name='deleted_at'
  )
  INTO has_deleted_at;

  IF has_deleted_at THEN
    del_filter := ' AND wa.deleted_at IS NULL ';
  ELSE
    del_filter := '';
  END IF;

  -- detect "platform/user" discriminator column (optional)
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='wallet_accounts' AND column_name='owner_kind'
  ) THEN
    col_owner_kind := 'owner_kind';
  ELSIF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='wallet_accounts' AND column_name='owner_type'
  ) THEN
    col_owner_kind := 'owner_type';
  ELSIF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='wallet_accounts' AND column_name='wallet_owner_kind'
  ) THEN
    col_owner_kind := 'wallet_owner_kind';
  ELSIF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='wallet_accounts' AND column_name='account_kind'
  ) THEN
    col_owner_kind := 'account_kind';
  END IF;

  -- detect user id column
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='wallet_accounts' AND column_name='owner_user_id'
  ) THEN
    col_user_id := 'owner_user_id';
  ELSIF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='wallet_accounts' AND column_name='user_id'
  ) THEN
    col_user_id := 'user_id';
  ELSIF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='wallet_accounts' AND column_name='owner_id'
  ) THEN
    col_user_id := 'owner_id';
  END IF;

  -- PLATFORM wallet lookup
  IF p_beneficiary_kind = 'platform' THEN
    -- Prefer explicit kind/type column if it exists
    IF col_owner_kind IS NOT NULL THEN
      q := format(
        'SELECT wa.id
         FROM public.wallet_accounts wa
         WHERE wa.organization_id = $1
           AND wa.%I::text = ''platform'' %s
         ORDER BY wa.created_at ASC
         LIMIT 1',
        col_owner_kind,
        del_filter
      );
      EXECUTE q INTO v_id USING p_org;
      IF v_id IS NOT NULL THEN
        RETURN v_id;
      END IF;
    END IF;

    -- Fallback: platform wallet is a row with NULL user owner (your schema uses user_id NULL + is_platform_wallet=true)
    IF col_user_id IS NOT NULL THEN
      q := format(
        'SELECT wa.id
         FROM public.wallet_accounts wa
         WHERE wa.organization_id = $1
           AND wa.%I IS NULL %s
         ORDER BY wa.created_at ASC
         LIMIT 1',
        col_user_id,
        del_filter
      );
      EXECUTE q INTO v_id USING p_org;
      RETURN v_id;
    END IF;

    RETURN NULL;
  END IF;

  -- USER wallet lookup
  IF p_beneficiary_kind = 'user' THEN
    IF col_user_id IS NULL THEN
      RETURN NULL;
    END IF;

    q := format(
      'SELECT wa.id
       FROM public.wallet_accounts wa
       WHERE wa.organization_id = $1
         AND wa.%I = $2 %s
       ORDER BY wa.created_at ASC
       LIMIT 1',
      col_user_id,
      del_filter
    );
    EXECUTE q INTO v_id USING p_org, p_user_id;
    RETURN v_id;
  END IF;

  RETURN NULL;
END;
$function$;

SELECT 'find_wallet_account_id patched' AS ok;
SQL

echo ""
echo "✅ Patched. Now retry:"
echo "  psql -d $DB -X -v ON_ERROR_STOP=1 -c \"update public.payments set status='successful'::public.payment_status where id='b77e1471-ef74-43fe-baf7-1accd5717679'::uuid;\""
echo ""
echo "Then check credits:"
echo "  psql -d $DB -X -P pager=off -c \"select txn_type::text, amount, currency, reference_type, reference_id, created_at from public.wallet_transactions where reference_type='payment' and reference_id='b77e1471-ef74-43fe-baf7-1accd5717679'::uuid order by created_at desc;\""
