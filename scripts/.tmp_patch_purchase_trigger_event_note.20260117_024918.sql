BEGIN;

-- Patch: make purchase trigger read app.event_note (optional) into purchase_events.metadata.note
-- This does NOT change existing note column usage; it enriches metadata with the note.
-- Expect API to set: select set_config('app.event_note', '<text>', true);

CREATE OR REPLACE FUNCTION public.trg_property_purchases_transition_and_log()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
  old_status text;
  new_status text;
  old_pay text;
  new_pay text;
  actor uuid;
  event_note text;
BEGIN
  old_status := COALESCE(OLD.status::text, NULL);
  new_status := COALESCE(NEW.status::text, NULL);

  old_pay := COALESCE(OLD.payment_status::text, NULL);
  new_pay := COALESCE(NEW.payment_status::text, NULL);

  -- Actor priority:
  -- 1) app.user_id set by API (JWT)
  -- 2) refunded_by (for refund event)
  -- 3) buyer_id (last fallback)
  actor := COALESCE(
    public.current_app_user_uuid(),
    NEW.refunded_by,
    NEW.buyer_id
  );

  -- Optional note from API/session
  BEGIN
    event_note := nullif(current_setting('app.event_note', true), '');
  EXCEPTION WHEN others THEN
    event_note := null;
  END;

  -- AUTO-SYNC: keep status aligned with payment_status
  IF old_pay IS DISTINCT FROM new_pay THEN
    IF new_pay = 'paid' AND NEW.status::text = 'under_contract' THEN
      NEW.status := 'paid'::purchase_status;
      new_status := 'paid';
    ELSIF new_pay = 'refunded' THEN
      NEW.status := 'refunded'::purchase_status;
      new_status := 'refunded';
    END IF;
  END IF;

  -- enforce transitions (your existing enforcement)
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
        jsonb_strip_nulls(
          jsonb_build_object('source','trigger','event_note', event_note)
        )
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
        jsonb_strip_nulls(
          jsonb_build_object(
            'source','trigger',
            'refund_method', NEW.refund_method,
            'refund_payment_id', NEW.refund_payment_id,
            'refunded_reason', NEW.refunded_reason,
            'event_note', event_note
          )
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
        jsonb_strip_nulls(
          jsonb_build_object('source','trigger','event_note', event_note)
        )
      );
    END IF;
  END IF;

  -- log business status events (DEDUPED)
  IF old_status IS DISTINCT FROM new_status THEN
    IF old_pay IS DISTINCT FROM new_pay AND new_status IN ('paid','refunded') THEN
      -- If status changed only because we auto-synced from payment_status,
      -- skip generic status_changed (we already logged paid/refunded above)
      NULL;
    ELSE
      INSERT INTO public.purchase_events(
        organization_id, purchase_id, event_type, actor_user_id,
        from_status, to_status, note, metadata
      ) VALUES (
        NEW.organization_id, NEW.id, 'status_changed',
        actor,
        old_status, new_status,
        'status changed',
        jsonb_strip_nulls(
          jsonb_build_object('source','trigger','event_note', event_note)
        )
      );
    END IF;

    -- Keep your completed event behavior
    IF new_status = 'completed' THEN
      INSERT INTO public.purchase_events(
        organization_id, purchase_id, event_type, actor_user_id,
        from_status, to_status, note, metadata
      ) VALUES (
        NEW.organization_id, NEW.id, 'completed',
        actor,
        old_status, new_status,
        'purchase completed',
        jsonb_strip_nulls(
          jsonb_build_object('source','trigger','event_note', event_note)
        )
      );
    END IF;
  END IF;

  RETURN NEW;
END
$function$;

COMMIT;

-- Show trigger (sanity)
SELECT tgname, tgenabled, pg_get_triggerdef(oid) AS def
FROM pg_trigger
WHERE tgname='property_purchases_transition_and_log';
