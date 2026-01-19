-- Option 1: add dedicated rent payment tables that do NOT use public.payments
-- so we avoid the payments.amount == listing.listed_price trigger.

BEGIN;

-- 1) rent_payments (one per rent invoice pay)
CREATE TABLE IF NOT EXISTS public.rent_payments (
  id              uuid PRIMARY KEY DEFAULT rentease_uuid(),
  organization_id uuid NOT NULL DEFAULT current_organization_uuid() REFERENCES public.organizations(id),

  invoice_id   uuid NOT NULL REFERENCES public.rent_invoices(id) ON DELETE CASCADE,
  tenancy_id   uuid NOT NULL REFERENCES public.tenancies(id) ON DELETE RESTRICT,
  tenant_id    uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  property_id  uuid NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,

  amount        numeric(15,2) NOT NULL CHECK (amount > 0),
  currency      varchar(3) DEFAULT 'USD',
  payment_method text NOT NULL,
  status        text NOT NULL DEFAULT 'successful',

  created_at    timestamptz NOT NULL DEFAULT now()
);

-- Ensure one rent_payment per invoice (idempotent safety)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname='public'
      AND indexname='uniq_rent_payments_invoice'
  ) THEN
    CREATE UNIQUE INDEX uniq_rent_payments_invoice
      ON public.rent_payments(invoice_id);
  END IF;
END$$;

ALTER TABLE public.rent_payments ENABLE ROW LEVEL SECURITY;

-- Allow admin/service to write; allow invoice viewers to read
DO $$
BEGIN
  -- SELECT policy
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='rent_payments' AND policyname='rent_payments_select'
  ) THEN
    EXECUTE $p$
      CREATE POLICY rent_payments_select ON public.rent_payments
      FOR SELECT
      USING (
        organization_id = current_organization_uuid()
        AND EXISTS (
          SELECT 1
          FROM public.rent_invoices ri
          WHERE ri.id = rent_payments.invoice_id
            AND ri.deleted_at IS NULL
            AND ri.organization_id = current_organization_uuid()
            AND (is_admin() OR ri.tenant_id = current_user_uuid() OR is_property_owner_or_default_agent(ri.property_id))
        )
      );
    $p$;
  END IF;

  -- INSERT/UPDATE/DELETE policy
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='rent_payments' AND policyname='rent_payments_write_admin_or_service'
  ) THEN
    EXECUTE $p$
      CREATE POLICY rent_payments_write_admin_or_service ON public.rent_payments
      FOR ALL
      USING (is_admin() OR CURRENT_USER = 'rentease_service')
      WITH CHECK (organization_id = current_organization_uuid() AND (is_admin() OR CURRENT_USER = 'rentease_service'));
    $p$;
  END IF;
END$$;

-- 2) rent_invoice_payments (parallel to invoice_payments but points to rent_payments)
CREATE TABLE IF NOT EXISTS public.rent_invoice_payments (
  id              uuid PRIMARY KEY DEFAULT rentease_uuid(),
  organization_id uuid DEFAULT current_organization_uuid() REFERENCES public.organizations(id),

  invoice_id       uuid NOT NULL REFERENCES public.rent_invoices(id) ON DELETE CASCADE,
  rent_payment_id  uuid NOT NULL REFERENCES public.rent_payments(id) ON DELETE RESTRICT,

  amount           numeric(15,2) NOT NULL CHECK (amount > 0),
  created_at       timestamptz NOT NULL DEFAULT now()
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname='public'
      AND indexname='uniq_rent_invoice_payments_invoice'
  ) THEN
    CREATE UNIQUE INDEX uniq_rent_invoice_payments_invoice
      ON public.rent_invoice_payments(invoice_id);
  END IF;
END$$;

ALTER TABLE public.rent_invoice_payments ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='rent_invoice_payments' AND policyname='rent_invoice_payments_select'
  ) THEN
    EXECUTE $p$
      CREATE POLICY rent_invoice_payments_select ON public.rent_invoice_payments
      FOR SELECT
      USING (
        organization_id = current_organization_uuid()
        AND EXISTS (
          SELECT 1
          FROM public.rent_invoices ri
          WHERE ri.id = rent_invoice_payments.invoice_id
            AND ri.deleted_at IS NULL
            AND ri.organization_id = current_organization_uuid()
            AND (is_admin() OR ri.tenant_id = current_user_uuid() OR is_property_owner_or_default_agent(ri.property_id))
        )
      );
    $p$;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='rent_invoice_payments' AND policyname='rent_invoice_payments_write_admin_or_service'
  ) THEN
    EXECUTE $p$
      CREATE POLICY rent_invoice_payments_write_admin_or_service ON public.rent_invoice_payments
      FOR ALL
      USING (is_admin() OR CURRENT_USER = 'rentease_service')
      WITH CHECK (organization_id = current_organization_uuid() AND (is_admin() OR CURRENT_USER = 'rentease_service'));
    $p$;
  END IF;
END$$;

-- 3) wallet_transactions idempotency for rent_invoice credits
-- Your current unique index only covers reference_type='payment'. We add another for rent_invoice.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='public'
      AND indexname='uniq_wallet_tx_rent_invoice_credit'
  ) THEN
    CREATE UNIQUE INDEX uniq_wallet_tx_rent_invoice_credit
      ON public.wallet_transactions(wallet_account_id, reference_type, reference_id, txn_type)
      WHERE reference_type = 'rent_invoice';
  END IF;
END$$;

COMMIT;
