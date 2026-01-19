#!/usr/bin/env bash
set -eo pipefail
: "${DB_NAME:?DB_NAME not set}"

psql -d "$DB_NAME" <<'SQL'
BEGIN;

-- Minimal purchase status enum (safe if already exists)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'purchase_status') THEN
    CREATE TYPE purchase_status AS ENUM ('draft','agreement','escrow','paid','completed','cancelled');
  END IF;
END$$;

-- Purchase order / closing tracker
CREATE TABLE IF NOT EXISTS public.property_purchases (
  id uuid PRIMARY KEY DEFAULT rentease_uuid(),
  organization_id uuid NOT NULL DEFAULT current_organization_uuid() REFERENCES public.organizations(id),
  property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,

  buyer_id uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  seller_id uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,

  agreed_price numeric(15,2) NOT NULL,
  currency varchar(3) DEFAULT 'USD',

  status purchase_status NOT NULL DEFAULT 'agreement',

  escrow_amount numeric(15,2),
  escrow_paid_at timestamptz,

  closing_date date,
  completed_at timestamptz,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_property_purchases_org ON public.property_purchases(organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_property_purchases_property ON public.property_purchases(property_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_property_purchases_buyer ON public.property_purchases(buyer_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_property_purchases_seller ON public.property_purchases(seller_id, created_at DESC);

-- trigger updated_at (if your set_updated_at() exists)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname='set_updated_at') THEN
    BEGIN
      CREATE TRIGGER set_updated_at_property_purchases
      BEFORE UPDATE ON public.property_purchases
      FOR EACH ROW EXECUTE FUNCTION set_updated_at();
    EXCEPTION WHEN duplicate_object THEN
      -- ignore
      NULL;
    END;
  END IF;
END$$;

COMMIT;
SQL

echo "✅ purchase tables ready"
