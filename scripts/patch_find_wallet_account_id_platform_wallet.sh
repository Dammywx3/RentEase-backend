#!/usr/bin/env bash
set -euo pipefail

DB="${DB:-rentease}"

echo "== Patch find_wallet_account_id(): use is_platform_wallet + currency =="
echo "DB: $DB"
echo ""

psql -d "$DB" -X -v ON_ERROR_STOP=1 <<'SQL'
CREATE OR REPLACE FUNCTION public.find_wallet_account_id(
  p_org uuid,
  p_beneficiary_kind text,
  p_user_id uuid,
  p_currency text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
AS $function$
DECLARE
  v_id uuid;
  v_cur text := NULLIF(trim(COALESCE(p_currency,'')), '');
BEGIN
  -- Normalize currency (optional)
  IF v_cur IS NOT NULL THEN
    v_cur := upper(v_cur);
  END IF;

  -- PLATFORM wallet lookup
  IF p_beneficiary_kind = 'platform' THEN
    IF v_cur IS NOT NULL THEN
      SELECT wa.id
      INTO v_id
      FROM public.wallet_accounts wa
      WHERE wa.organization_id = p_org
        AND wa.is_platform_wallet = true
        AND upper(COALESCE(wa.currency,'')) = v_cur
      ORDER BY wa.created_at ASC
      LIMIT 1;
    ELSE
      SELECT wa.id
      INTO v_id
      FROM public.wallet_accounts wa
      WHERE wa.organization_id = p_org
        AND wa.is_platform_wallet = true
      ORDER BY wa.created_at ASC
      LIMIT 1;
    END IF;

    RETURN v_id;
  END IF;

  -- USER wallet lookup
  IF p_beneficiary_kind = 'user' THEN
    IF p_user_id IS NULL THEN
      RETURN NULL;
    END IF;

    IF v_cur IS NOT NULL THEN
      SELECT wa.id
      INTO v_id
      FROM public.wallet_accounts wa
      WHERE wa.organization_id = p_org
        AND wa.user_id = p_user_id
        AND upper(COALESCE(wa.currency,'')) = v_cur
      ORDER BY wa.created_at ASC
      LIMIT 1;
    ELSE
      SELECT wa.id
      INTO v_id
      FROM public.wallet_accounts wa
      WHERE wa.organization_id = p_org
        AND wa.user_id = p_user_id
      ORDER BY wa.created_at ASC
      LIMIT 1;
    END IF;

    RETURN v_id;
  END IF;

  RETURN NULL;
END;
$function$;

SELECT 'find_wallet_account_id upgraded (platform wallet safe)' AS ok;
SQL

echo ""
echo "✅ Done."
echo "Next: patch wallet_credit_from_splits() to pass currency into helper."
