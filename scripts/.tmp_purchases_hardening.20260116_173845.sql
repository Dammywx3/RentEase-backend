-- ==========================================================
-- Purchases Hardening Pack
-- (A) Status transitions + (B) purchase_events timeline
-- ==========================================================

BEGIN;

-- ---------------------------
-- 1) Create a purchase_event_type enum (safe)
-- ---------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'purchase_event_type') THEN
    CREATE TYPE purchase_event_type AS ENUM (
      'created',
      'status_changed',
      'paid',
      'completed',
      'refunded'
    );
  END IF;
END $$;

-- ---------------------------
-- 2) purchase_events table
-- ---------------------------
CREATE TABLE IF NOT EXISTS public.purchase_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  purchase_id uuid NOT NULL REFERENCES public.property_purchases(id) ON DELETE CASCADE,

  event_type purchase_event_type NOT NULL,
  actor_user_id uuid NULL REFERENCES public.users(id),

  -- snapshots / metadata (lightweight, flexible)
  from_status text NULL,
  to_status text NULL,
  note text NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_purchase_events_org_purchase_time
  ON public.purchase_events(organization_id, purchase_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_purchase_events_purchase_time
  ON public.purchase_events(purchase_id, created_at DESC);

-- ---------------------------
-- 3) Allowed status transition guard
-- (Assumes property_purchases.status is a textual enum-ish column.
-- If it's an enum, ::text works and comparisons still OK.)
-- ---------------------------
CREATE OR REPLACE FUNCTION public.assert_purchase_transition(
  old_status text,
  new_status text,
  old_payment_status text,
  new_payment_status text
) RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  -- no change -> ok
  IF (old_status IS NOT DISTINCT FROM new_status)
     AND (old_payment_status IS NOT DISTINCT FROM new_payment_status) THEN
    RETURN;
  END IF;

  -- -----------------------------------------
  -- Payment transitions
  -- -----------------------------------------
  -- allowed:
  --   paid -> refunded
  --   refunded -> refunded (idempotent)
  IF old_payment_status = 'paid' AND new_payment_status = 'refunded' THEN
    RETURN;
  END IF;

  IF old_payment_status = 'refunded' AND new_payment_status = 'refunded' THEN
    RETURN;
  END IF;

  -- allow initial -> paid (your pay service likely sets this)
  IF (old_payment_status IS NULL OR old_payment_status = '' OR old_payment_status = 'unpaid')
     AND new_payment_status = 'paid' THEN
    RETURN;
  END IF;

  -- if payment_status changes in any other way, block
  IF old_payment_status IS DISTINCT FROM new_payment_status THEN
    RAISE EXCEPTION 'Illegal payment_status transition: % -> %', old_payment_status, new_payment_status
      USING ERRCODE='check_violation';
  END IF;

  -- -----------------------------------------
  -- Status transitions (business status)
  -- under_contract -> paid -> completed
  -- (we allow "status" to stay under_contract while payment_status flips to paid if your app does that)
  -- -----------------------------------------
  IF old_status = 'under_contract' AND new_status = 'paid' THEN
    RETURN;
  END IF;

  IF old_status = 'paid' AND new_status = 'completed' THEN
    RETURN;
  END IF;

  -- allow idempotent no-op repeats
  IF old_status IS NOT DISTINCT FROM new_status THEN
    RETURN;
  END IF;

  -- otherwise block
  RAISE EXCEPTION 'Illegal status transition: % -> %', old_status, new_status
    USING ERRCODE='check_violation';
END $$;

-- ---------------------------
-- 4) Trigger: enforce transitions + log events
-- ---------------------------
CREATE OR REPLACE FUNCTION public.trg_property_purchases_transition_and_log()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  old_status text;
  new_status text;
  old_pay text;
  new_pay text;
BEGIN
  old_status := COALESCE(OLD.status::text, NULL);
  new_status := COALESCE(NEW.status::text, NULL);

  old_pay := COALESCE(OLD.payment_status::text, NULL);
  new_pay := COALESCE(NEW.payment_status::text, NULL);

  -- enforce
  PERFORM public.assert_purchase_transition(old_status, new_status, old_pay, new_pay);

  -- log payment events
  IF old_pay IS DISTINCT FROM new_pay THEN
    IF new_pay = 'paid' THEN
      INSERT INTO public.purchase_events(
        organization_id, purchase_id, event_type, actor_user_id,
        from_status, to_status, note, metadata
      ) VALUES (
        NEW.organization_id, NEW.id, 'paid',
        NEW.buyer_id, -- best-effort default; API can insert explicit actor too
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
        NEW.refunded_by,
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
        NULL,
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
      NULL,
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
        NULL,
        old_status, new_status,
        'purchase completed',
        jsonb_build_object('source','trigger')
      );
    END IF;
  END IF;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS property_purchases_transition_and_log ON public.property_purchases;
CREATE TRIGGER property_purchases_transition_and_log
BEFORE UPDATE OF status, payment_status, refund_method, refunded_reason, refunded_by, refund_payment_id
ON public.property_purchases
FOR EACH ROW
EXECUTE FUNCTION public.trg_property_purchases_transition_and_log();

COMMIT;
