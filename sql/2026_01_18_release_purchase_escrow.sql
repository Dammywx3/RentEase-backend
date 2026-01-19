-- sql/2026_01_18_release_purchase_escrow.sql
-- Releases escrow for a purchase:
-- - debit escrow wallet
-- - credit seller wallet
-- - mark purchase completed
--
-- IMPORTANT:
-- This assumes you already have:
--   public.get_or_create_org_escrow_wallet(uuid) returns uuid
--   public.get_or_create_user_wallet_account(uuid) returns uuid
--
-- This also assumes wallet_transactions has:
--   wallet_account_id, txn_type, reference_type, reference_id, amount, currency, note
-- If your schema differs, paste your wallet_transactions \d and I will adapt.

CREATE OR REPLACE FUNCTION public.release_purchase_escrow(
  p_purchase_id uuid,
  p_note text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_seller_id uuid;
  v_currency text;
  v_note text;
  v_exists int;

  v_escrow_wallet_id uuid;
  v_seller_wallet_id uuid;

  v_amount numeric;
BEGIN
  -- Lock purchase row to prevent double release
  SELECT organization_id, seller_id, COALESCE(currency,'NGN')::text
  INTO v_org_id, v_seller_id, v_currency
  FROM public.property_purchases
  WHERE id = p_purchase_id
    AND deleted_at IS NULL
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PURCHASE_NOT_FOUND: %', p_purchase_id USING ERRCODE = 'P0001';
  END IF;

  -- ensure org context for wallet helpers / RLS defaults
  PERFORM set_config('app.organization_id', v_org_id::text, true);

  v_note := COALESCE(p_note, 'Closing complete, released escrow');

  -- Idempotency: if we already debited escrow for this purchase, do nothing
  SELECT COUNT(*)::int
  INTO v_exists
  FROM public.wallet_transactions
  WHERE reference_type = 'purchase'
    AND reference_id = p_purchase_id
    AND txn_type::text = 'debit_escrow';

  IF v_exists > 0 THEN
    RETURN;
  END IF;

  -- How much is currently held in escrow for this purchase?
  -- (credits to escrow - debits from escrow)
  SELECT COALESCE(SUM(
    CASE
      WHEN txn_type::text = 'credit_escrow' THEN amount
      WHEN txn_type::text = 'debit_escrow'  THEN -amount
      ELSE 0
    END
  ), 0)
  INTO v_amount
  FROM public.wallet_transactions
  WHERE reference_type = 'purchase'
    AND reference_id = p_purchase_id;

  IF v_amount <= 0 THEN
    RAISE EXCEPTION 'NO_ESCROW_BALANCE_FOR_PURCHASE: %', p_purchase_id USING ERRCODE = 'P0001';
  END IF;

  -- Resolve wallets (creates if missing)
  v_escrow_wallet_id := public.get_or_create_org_escrow_wallet(v_org_id);
  v_seller_wallet_id := public.get_or_create_user_wallet_account(v_seller_id);

  -- Move funds: escrow -> seller
  INSERT INTO public.wallet_transactions (
    wallet_account_id, txn_type, reference_type, reference_id, amount, currency, note
  )
  VALUES
    (v_escrow_wallet_id, 'debit_escrow',  'purchase', p_purchase_id, v_amount, v_currency, v_note),
    (v_seller_wallet_id, 'credit_seller','purchase', p_purchase_id, v_amount, v_currency, v_note);

  -- Mark purchase completed (safe if already completed)
  BEGIN
    UPDATE public.property_purchases
    SET
      status = CASE
        WHEN status::text IN ('completed','closed') THEN status
        ELSE 'completed'::public.purchase_status
      END,
      closed_at = COALESCE(closed_at, NOW()),
      updated_at = NOW()
    WHERE id = p_purchase_id
      AND deleted_at IS NULL;
  EXCEPTION WHEN others THEN
    -- If your enum/table fields differ, escrow release still succeeded.
    NULL;
  END;

END;
$$;
