BEGIN;

-- 1) Audit log table (create if missing)
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id uuid PRIMARY KEY DEFAULT rentease_uuid(),
  organization_id uuid NOT NULL DEFAULT current_organization_uuid() REFERENCES public.organizations(id),
  actor_user_id uuid REFERENCES public.users(id),
  action text NOT NULL,
  entity_type text,
  entity_id uuid,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_org_created ON public.audit_logs(organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity ON public.audit_logs(entity_type, entity_id, created_at DESC);

-- 2) Idempotency guard for escrow release:
-- Ensure only ONE escrow release debit exists per purchase (prevents double-close)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema='public' AND table_name='wallet_transactions'
  ) THEN
    -- You may already have a unique constraint; add only if missing
    IF NOT EXISTS (
      SELECT 1
      FROM pg_constraint c
      JOIN pg_class t ON t.oid=c.conrelid
      JOIN pg_namespace n ON n.oid=t.relnamespace
      WHERE n.nspname='public'
        AND t.relname='wallet_transactions'
        AND c.conname='uniq_wallet_txn_purchase_release'
    ) THEN
      -- This assumes txn_type exists and uses 'debit_escrow' for release.
      -- Also assumes reference_type='purchase' and reference_id=purchase_id are stored.
      EXECUTE $q$
        CREATE UNIQUE INDEX uniq_wallet_txn_purchase_release
        ON public.wallet_transactions(reference_type, reference_id, txn_type, amount, currency)
        WHERE reference_type='purchase' AND txn_type='debit_escrow'
      $q$;
    END IF;
  END IF;
END $$;

COMMIT;
