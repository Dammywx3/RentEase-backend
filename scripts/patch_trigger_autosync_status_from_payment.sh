#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

DB_NAME="${DB_NAME:-rentease}"
TS="$(date +%Y%m%d_%H%M%S)"
SQL_FILE="scripts/.tmp_patch_trigger_autosync_status.${TS}.sql"

echo "==> ROOT=$ROOT"
echo "==> DB_NAME=$DB_NAME"
echo "==> Writing $SQL_FILE"

cat > "$SQL_FILE" <<'SQL'
BEGIN;

-- Patch trigger function to AUTO-SYNC business status from payment_status
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
  -- 1) app.user_id set by API (JWT -> set_config)
  -- 2) refunded_by (refund flow)
  -- 3) buyer_id (fallback)
  actor := COALESCE(
    public.current_app_user_uuid(),
    NEW.refunded_by,
    NEW.buyer_id
  );

  -- ✅ AUTO-SYNC: keep status aligned with payment_status
  IF old_pay IS DISTINCT FROM new_pay THEN
    IF new_pay = 'paid' AND COALESCE(NEW.status::text,'') = 'under_contract' THEN
      NEW.status := 'paid'::purchase_status;
      new_status := 'paid';
    ELSIF new_pay = 'refunded' THEN
      NEW.status := 'refunded'::purchase_status;
      new_status := 'refunded';
    END IF;
  END IF;

  -- Enforce transitions (now compatible with AUTO-SYNC)
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

    IF new_status = 'closed' THEN
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

-- Verify trigger exists + points at correct function
SELECT
  tgname,
  tgenabled,
  pg_get_triggerdef(t.oid) as def
FROM pg_trigger t
JOIN pg_class c ON c.oid=t.tgrelid
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public'
  AND c.relname='property_purchases'
  AND tgname='property_purchases_transition_and_log';
SQL

echo "==> Applying $SQL_FILE to DB_NAME=$DB_NAME ..."
psql -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$SQL_FILE"
echo "✅ AUTO-SYNC trigger patch applied."
