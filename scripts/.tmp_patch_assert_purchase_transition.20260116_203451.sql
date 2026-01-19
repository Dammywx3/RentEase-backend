BEGIN;

-- Patch transition enforcement so AUTO-SYNC (status follows payment_status) won't break.
CREATE OR REPLACE FUNCTION public.assert_purchase_transition(
  old_status text,
  new_status text,
  old_pay text,
  new_pay text
) RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  -- helper order for normal forward business flow
  old_rank int;
  new_rank int;

  FUNCTION status_rank(s text) RETURNS int
  LANGUAGE plpgsql
  AS $f$
  BEGIN
    RETURN CASE s
      WHEN 'initiated'         THEN 10
      WHEN 'offer_made'        THEN 20
      WHEN 'offer_accepted'    THEN 30
      WHEN 'under_contract'    THEN 40
      WHEN 'paid'              THEN 50
      WHEN 'escrow_opened'     THEN 60
      WHEN 'deposit_paid'      THEN 70
      WHEN 'inspection'        THEN 80
      WHEN 'financing'         THEN 90
      WHEN 'appraisal'         THEN 100
      WHEN 'title_search'      THEN 110
      WHEN 'closing_scheduled' THEN 120
      WHEN 'closed'            THEN 130
      WHEN 'cancelled'         THEN 900
      WHEN 'refunded'          THEN 950
      ELSE 0
    END;
  END;
  $f$;

BEGIN
  -- -----------------------------
  -- A) PAYMENT STATUS transitions
  -- -----------------------------
  IF old_pay IS DISTINCT FROM new_pay THEN
    -- Normalize nulls
    old_pay := COALESCE(old_pay, '');
    new_pay := COALESCE(new_pay, '');

    -- Allowed:
    -- unpaid -> paid
    -- paid -> refunded
    -- (also allow idempotent repeats handled elsewhere; this just validates)
    IF NOT (
      (old_pay IN ('', 'unpaid') AND new_pay = 'paid') OR
      (old_pay = 'paid' AND new_pay = 'refunded') OR
      (old_pay = new_pay) OR
      (old_pay = '' AND new_pay = '')  -- no-op
    ) THEN
      RAISE EXCEPTION 'Illegal payment_status transition: % -> %', old_pay, new_pay
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  -- -----------------------------
  -- B) BUSINESS STATUS transitions
  -- -----------------------------
  IF old_status IS DISTINCT FROM new_status THEN
    old_status := COALESCE(old_status, '');
    new_status := COALESCE(new_status, '');

    -- Terminal states: block changing away from them
    IF old_status IN ('closed','cancelled','refunded') AND new_status <> old_status THEN
      RAISE EXCEPTION 'Cannot transition out of terminal status: % -> %', old_status, new_status
        USING ERRCODE = 'P0001';
    END IF;

    -- AUTO-SYNC allowances:
    -- When payment becomes paid/refunded, status may be set to paid/refunded.
    IF (new_pay = 'paid' AND new_status = 'paid') THEN
      RETURN;
    END IF;

    IF (new_pay = 'refunded' AND new_status = 'refunded') THEN
      RETURN;
    END IF;

    -- Allow cancellation from most non-terminal states
    IF new_status = 'cancelled' THEN
      RETURN;
    END IF;

    -- Normal forward-only progression by rank
    old_rank := status_rank(old_status);
    new_rank := status_rank(new_status);

    -- If either is unknown, block it (forces you to keep enum + logic aligned)
    IF old_rank = 0 OR new_rank = 0 THEN
      RAISE EXCEPTION 'Unknown purchase_status in transition: % -> %', old_status, new_status
        USING ERRCODE = 'P0001';
    END IF;

    -- Allow staying the same
    IF old_rank = new_rank THEN
      RETURN;
    END IF;

    -- Allow forward only
    IF new_rank < old_rank THEN
      RAISE EXCEPTION 'Backward status transition not allowed: % -> %', old_status, new_status
        USING ERRCODE = 'P0001';
    END IF;

    -- Otherwise OK (forward progress)
    RETURN;
  END IF;

END;
$$;

COMMIT;

-- quick visibility
DO $$
DECLARE r record;
BEGIN
  RAISE NOTICE 'purchase_status enum values:';
  FOR r IN
    SELECT e.enumlabel
    FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    WHERE t.typname='purchase_status'
    ORDER BY e.enumsortorder
  LOOP
    RAISE NOTICE ' - %', r.enumlabel;
  END LOOP;
END $$;

