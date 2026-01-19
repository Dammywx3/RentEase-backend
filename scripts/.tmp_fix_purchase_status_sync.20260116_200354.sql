BEGIN;

-- ------------------------------------------------------------
-- 0) Detect status column type (enum vs text)
-- ------------------------------------------------------------
DO $$
DECLARE
  status_udt text;
BEGIN
  SELECT c.udt_name
    INTO status_udt
  FROM information_schema.columns c
  WHERE c.table_schema='public'
    AND c.table_name='property_purchases'
    AND c.column_name='status';

  IF status_udt IS NULL THEN
    RAISE EXCEPTION 'public.property_purchases.status not found';
  END IF;

  RAISE NOTICE 'property_purchases.status udt_name=%', status_udt;
END $$;

-- ------------------------------------------------------------
-- 1) If status is an enum, ensure it contains paid/refunded/completed
-- ------------------------------------------------------------
DO $$
DECLARE
  status_udt text;
  is_enum boolean;
BEGIN
  SELECT c.udt_name
    INTO status_udt
  FROM information_schema.columns c
  WHERE c.table_schema='public'
    AND c.table_name='property_purchases'
    AND c.column_name='status';

  SELECT EXISTS(
    SELECT 1
    FROM pg_type t
    JOIN pg_namespace n ON n.oid=t.typnamespace
    WHERE n.nspname='public'
      AND t.typname=status_udt
      AND t.typtype='e'
  ) INTO is_enum;

  IF is_enum THEN
    -- add enum values only if missing
    IF NOT EXISTS (
      SELECT 1 FROM pg_enum e
      JOIN pg_type t ON t.oid=e.enumtypid
      JOIN pg_namespace n ON n.oid=t.typnamespace
      WHERE n.nspname='public'
        AND t.typname=status_udt
        AND e.enumlabel='paid'
    ) THEN
      EXECUTE format('ALTER TYPE public.%I ADD VALUE %L', status_udt, 'paid');
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM pg_enum e
      JOIN pg_type t ON t.oid=e.enumtypid
      JOIN pg_namespace n ON n.oid=t.typnamespace
      WHERE n.nspname='public'
        AND t.typname=status_udt
        AND e.enumlabel='refunded'
    ) THEN
      EXECUTE format('ALTER TYPE public.%I ADD VALUE %L', status_udt, 'refunded');
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM pg_enum e
      JOIN pg_type t ON t.oid=e.enumtypid
      JOIN pg_namespace n ON n.oid=t.typnamespace
      WHERE n.nspname='public'
        AND t.typname=status_udt
        AND e.enumlabel='completed'
    ) THEN
      EXECUTE format('ALTER TYPE public.%I ADD VALUE %L', status_udt, 'completed');
    END IF;
  END IF;
END $$;

-- ------------------------------------------------------------
-- 2) Update trigger fn: sync status from payment_status
--    Keep your enforcement + audit logs.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_property_purchases_transition_and_log()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  old_status text;
  new_status text;
  old_pay text;
  new_pay text;
  actor uuid;
BEGIN
  old_status := COALESCE(OLD.status::text, NULL);
  new_status := COALESCE(NEW.status::text, NULL);

  old_pay := COALESCE(OLD.payment_status::text, NULL);
  new_pay := COALESCE(NEW.payment_status::text, NULL);

  -- Actor priority:
  -- 1) app.user_id set by API (JWT) on SAME connection
  -- 2) refunded_by (refund route writes it)
  -- 3) buyer_id
  actor := COALESCE(
    public.current_app_user_uuid(),
    NEW.refunded_by,
    NEW.buyer_id
  );

  -- ------------------------------------------------------------
  -- AUTO-SYNC STATUS BASED ON PAYMENT_STATUS CHANGE
  -- Only if caller didn't explicitly change status themselves.
  -- ------------------------------------------------------------
  IF old_pay IS DISTINCT FROM new_pay AND old_status IS NOT DISTINCT FROM new_status THEN
    -- unpaid -> paid => status becomes paid
    IF new_pay = 'paid' THEN
      NEW.status := 'paid';
      new_status := 'paid';
    END IF;

    -- paid -> refunded => status becomes refunded
    IF new_pay = 'refunded' THEN
      NEW.status := 'refunded';
      new_status := 'refunded';
    END IF;
  END IF;

  -- enforce allowed transitions (your existing function)
  PERFORM public.assert_purchase_transition(old_status, new_status, old_pay, new_pay);

  -- ------------------------------------------------------------
  -- Log payment events
  -- ------------------------------------------------------------
  IF old_pay IS DISTINCT FROM new_pay THEN
    IF new_pay = 'paid' THEN
      INSERT INTO public.purchase_events(
        organization_id, purchase_id, event_type, actor_user_id,
        from_status, to_status, note, metadata
      ) VALUES (
        NEW.organization_id, NEW.id, 'paid',
        actor,
        old_pay, new_pay,
        'payment_status changed to paid',
        jsonb_build_object('source','trigger')
      );
    ELSIF new_pay = 'refunded' THEN
      INSERT INTO public.purchase_events(
        organization_id, purchase_id, event_type, actor_user_id,
        from_status, to_status, note, metadata
      ) VALUES (
        NEW.organization_id, NEW.id, 'refunded',
        actor,
        old_pay, new_pay,
        'payment_status changed to refunded',
        jsonb_build_object(
          'source','trigger',
          'refund_method', NEW.refund_method,
          'refund_payment_id', NEW.refund_payment_id,
          'refunded_reason', NEW.refunded_reason
        )
      );
    ELSE
      INSERT INTO public.purchase_events(
        organization_id, purchase_id, event_type, actor_user_id,
        from_status, to_status, note, metadata
      ) VALUES (
        NEW.organization_id, NEW.id, 'status_changed',
        actor,
        old_pay, new_pay,
        'payment_status changed',
        jsonb_build_object('source','trigger')
      );
    END IF;
  END IF;

  -- ------------------------------------------------------------
  -- Log business status events
  -- ------------------------------------------------------------
  IF old_status IS DISTINCT FROM new_status THEN
    INSERT INTO public.purchase_events(
      organization_id, purchase_id, event_type, actor_user_id,
      from_status, to_status, note, metadata
    ) VALUES (
      NEW.organization_id, NEW.id, 'status_changed',
      actor,
      old_status, new_status,
      'status changed',
      jsonb_build_object('source','trigger')
    );

    IF new_status = 'completed' THEN
      INSERT INTO public.purchase_events(
        organization_id, purchase_id, event_type, actor_user_id,
        from_status, to_status, note, metadata
      ) VALUES (
        NEW.organization_id, NEW.id, 'completed',
        actor,
        old_status, new_status,
        'purchase completed',
        jsonb_build_object('source','trigger')
      );
    END IF;
  END IF;

  RETURN NEW;
END $$;

-- ------------------------------------------------------------
-- 3) Backfill: align status with payment_status for existing rows
-- ------------------------------------------------------------
-- paid -> status should be paid (if still under_contract)
UPDATE public.property_purchases
SET status = 'paid',
    updated_at = now()
WHERE payment_status::text = 'paid'
  AND status::text = 'under_contract';

-- refunded -> status should be refunded (if still under_contract/paid)
UPDATE public.property_purchases
SET status = 'refunded',
    updated_at = now()
WHERE payment_status::text = 'refunded'
  AND status::text <> 'refunded';

COMMIT;
