-- Patch: AUTO-SYNC status with payment_status in trg_property_purchases_transition_and_log()
-- Safe enum add: ensure purchase_status has 'paid' (in its own committed txn)

-- ==========================================================
-- PHASE 1: ensure enum purchase_status includes 'paid'
-- (must COMMIT before using new enum value)
-- ==========================================================
BEGIN;

DO $$
DECLARE
  has_paid boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    WHERE t.typname = 'purchase_status'
      AND e.enumlabel = 'paid'
  ) INTO has_paid;

  IF NOT has_paid THEN
    -- put 'paid' right after 'under_contract' if possible
    BEGIN
      EXECUTE 'ALTER TYPE purchase_status ADD VALUE ''paid'' AFTER ''under_contract''';
      RAISE NOTICE 'Added purchase_status value: paid (AFTER under_contract)';
    EXCEPTION WHEN syntax_error OR undefined_object THEN
      -- fallback for older PG that doesn't support AFTER
      EXECUTE 'ALTER TYPE purchase_status ADD VALUE ''paid''';
      RAISE NOTICE 'Added purchase_status value: paid (no AFTER available)';
    WHEN duplicate_object THEN
      RAISE NOTICE 'purchase_status already has value: paid';
    END;
  ELSE
    RAISE NOTICE 'purchase_status already has value: paid';
  END IF;
END $$;

COMMIT;

-- ==========================================================
-- PHASE 2: patch trigger function with AUTO-SYNC
-- ==========================================================
BEGIN;

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
  -- 1) app.user_id set by API (JWT / session)
  -- 2) refunded_by (for refund event)
  -- 3) buyer_id (last fallback)
  actor := COALESCE(
    public.current_app_user_uuid(),
    NEW.refunded_by,
    NEW.buyer_id
  );

  -- ----------------------------------------------------------
  -- AUTO-SYNC: keep status aligned with payment_status
  -- ----------------------------------------------------------
  IF old_pay IS DISTINCT FROM new_pay THEN
    IF new_pay = 'paid' AND NEW.status::text = 'under_contract' THEN
      NEW.status := 'paid'::purchase_status;
    ELSIF new_pay = 'refunded' THEN
      NEW.status := 'refunded'::purchase_status;
    END IF;
  END IF;

  -- refresh new_status after autosync
  new_status := COALESCE(NEW.status::text, NULL);

  -- enforce transition rules (your existing function)
  PERFORM public.assert_purchase_transition(old_status, new_status, old_pay, new_pay);

  -- log payment events
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

  -- log business status events
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

COMMIT;

-- ==========================================================
-- QUICK CHECKS
-- ==========================================================
-- show enum values (status)
SELECT e.enumlabel
FROM pg_enum e
JOIN pg_type t ON t.oid = e.enumtypid
WHERE t.typname='purchase_status'
ORDER BY e.enumsortorder;

-- confirm trigger exists
SELECT tgname, tgenabled
FROM pg_trigger t
JOIN pg_class c on c.oid=t.tgrelid
JOIN pg_namespace n on n.oid=c.relnamespace
WHERE n.nspname='public'
  AND c.relname='property_purchases'
  AND tgname='property_purchases_transition_and_log';
