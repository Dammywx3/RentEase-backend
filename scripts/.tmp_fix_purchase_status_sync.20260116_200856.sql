BEGIN;

-- 0) Safety: ensure helper functions exist (you already created these)
CREATE OR REPLACE FUNCTION public.current_app_user_uuid()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(current_setting('app.user_id', true), '')::uuid
$$;

CREATE OR REPLACE FUNCTION public.current_app_org_uuid()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(current_setting('app.organization_id', true), '')::uuid
$$;

-- 1) Ensure purchase_events exists and uses purchase_audit_event_type
-- (Your DB already has this; keep it safe.)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema='public' AND table_name='purchase_events'
  ) THEN
    CREATE TABLE public.purchase_events (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
      purchase_id uuid NOT NULL REFERENCES public.property_purchases(id) ON DELETE CASCADE,
      event_type purchase_audit_event_type NOT NULL,
      actor_user_id uuid NULL REFERENCES public.users(id),
      from_status text NULL,
      to_status text NULL,
      note text NULL,
      metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
      created_at timestamptz NOT NULL DEFAULT now()
    );

    CREATE INDEX idx_purchase_events_org_purchase_time
      ON public.purchase_events(organization_id, purchase_id, created_at DESC);

    CREATE INDEX idx_purchase_events_purchase_time
      ON public.purchase_events(purchase_id, created_at DESC);
  END IF;
END $$;

-- 2) Transition assert function (keep yours if already exists)
-- If missing, create a minimal one that only blocks crazy changes.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='assert_purchase_transition'
  ) THEN
    CREATE OR REPLACE FUNCTION public.assert_purchase_transition(
      old_status text,
      new_status text,
      old_payment_status text,
      new_payment_status text
    ) RETURNS void
    LANGUAGE plpgsql
    AS $fn$
    BEGIN
      -- allow no-op
      IF (old_status IS NOT DISTINCT FROM new_status)
         AND (old_payment_status IS NOT DISTINCT FROM new_payment_status) THEN
        RETURN;
      END IF;

      -- allow unpaid->paid and paid->refunded
      IF (coalesce(old_payment_status,'') IN ('','unpaid') AND new_payment_status='paid') THEN
        RETURN;
      END IF;

      IF (old_payment_status='paid' AND new_payment_status='refunded') THEN
        RETURN;
      END IF;

      -- allow status under_contract->paid->completed (business flow)
      IF old_status='under_contract' AND new_status='paid' THEN RETURN; END IF;
      IF old_status='paid' AND new_status='completed' THEN RETURN; END IF;

      -- otherwise block only if payment_status changes to something unexpected
      IF old_payment_status IS DISTINCT FROM new_payment_status THEN
        RAISE EXCEPTION 'Illegal payment_status transition: % -> %', old_payment_status, new_payment_status
          USING ERRCODE='check_violation';
      END IF;

      -- status changes outside the flow are blocked
      IF old_status IS DISTINCT FROM new_status THEN
        RAISE EXCEPTION 'Illegal status transition: % -> %', old_status, new_status
          USING ERRCODE='check_violation';
      END IF;
    END
    $fn$;
  END IF;
END $$;

-- 3) Replace trigger function with actor from app.user_id (session context)
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

  actor := COALESCE(
    public.current_app_user_uuid(),
    NEW.refunded_by,
    NEW.buyer_id
  );

  PERFORM public.assert_purchase_transition(old_status, new_status, old_pay, new_pay);

  -- payment events
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

  -- business status events
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

DROP TRIGGER IF EXISTS property_purchases_transition_and_log ON public.property_purchases;
CREATE TRIGGER property_purchases_transition_and_log
BEFORE UPDATE OF status, payment_status, refund_method, refunded_reason, refunded_by, refund_payment_id
ON public.property_purchases
FOR EACH ROW
EXECUTE FUNCTION public.trg_property_purchases_transition_and_log();

-- 4) Status sync repair (safe)
-- If payment_status is paid but status isn't paid, sync it.
-- (This update WILL fire trigger and log status_changed unless your assert blocks it;
--  so we do it carefully: only set status when it is currently under_contract)
UPDATE public.property_purchases
SET status = 'paid',
    updated_at = now()
WHERE payment_status::text = 'paid'
  AND status::text = 'under_contract';

COMMIT;

-- Quick report
SELECT
  status::text as status,
  payment_status::text as payment_status,
  count(*) as cnt
FROM public.property_purchases
WHERE deleted_at IS NULL
GROUP BY 1,2
ORDER BY 3 DESC;
