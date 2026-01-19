#!/usr/bin/env bash
set -euo pipefail

: "${DB_NAME:?DB_NAME is required}"

psql -d "$DB_NAME" -v ON_ERROR_STOP=1 <<'SQL'
CREATE OR REPLACE FUNCTION public.validate_payment_matches_listing()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  l_listed_price numeric(15,2);
  l_listing_property_id uuid;

  p_agreed_price numeric(15,2);
  p_currency varchar(3);
  p_property_id uuid;
  p_listing_id uuid;
  p_buyer_id uuid;
BEGIN
  -- =========================
  -- PURCHASE FLOW VALIDATION
  -- =========================
  IF NEW.reference_type = 'purchase' AND NEW.reference_id IS NOT NULL THEN
    SELECT agreed_price, currency, property_id, listing_id, buyer_id
      INTO p_agreed_price, p_currency, p_property_id, p_listing_id, p_buyer_id
    FROM public.property_purchases
    WHERE id = NEW.reference_id
      AND deleted_at IS NULL
    LIMIT 1;

    IF p_property_id IS NULL THEN
      RAISE EXCEPTION 'Purchase not found for reference_id=%', NEW.reference_id;
    END IF;

    IF NEW.amount <> p_agreed_price THEN
      RAISE EXCEPTION 'Payment.amount (%) must equal purchase.agreed_price (%)', NEW.amount, p_agreed_price;
    END IF;

    -- property must match the purchase
    IF NEW.property_id <> p_property_id THEN
      RAISE EXCEPTION 'Payment.property_id (%) must equal purchase.property_id (%)', NEW.property_id, p_property_id;
    END IF;

    -- buyer must be the payer (tenant_id in payments table)
    IF NEW.tenant_id <> p_buyer_id THEN
      RAISE EXCEPTION 'Payment.tenant_id (%) must equal purchase.buyer_id (%)', NEW.tenant_id, p_buyer_id;
    END IF;

    -- if purchase has listing_id, require payment listing_id to match it
    IF p_listing_id IS NOT NULL AND NEW.listing_id <> p_listing_id THEN
      RAISE EXCEPTION 'Payment.listing_id (%) must equal purchase.listing_id (%)', NEW.listing_id, p_listing_id;
    END IF;

    -- currency: if not set, default to purchase currency; if set, must match
    IF NEW.currency IS NULL THEN
      NEW.currency := p_currency;
    ELSIF NEW.currency <> p_currency THEN
      RAISE EXCEPTION 'Payment.currency (%) must equal purchase.currency (%)', NEW.currency, p_currency;
    END IF;

    RETURN NEW;
  END IF;

  -- =========================
  -- DEFAULT LISTING VALIDATION
  -- =========================
  SELECT listed_price, property_id
    INTO l_listed_price, l_listing_property_id
  FROM public.property_listings
  WHERE id = NEW.listing_id
    AND deleted_at IS NULL
  LIMIT 1;

  IF l_listing_property_id IS NULL THEN
    RAISE EXCEPTION 'Listing not found for listing_id=%', NEW.listing_id;
  END IF;

  IF NEW.amount <> l_listed_price THEN
    RAISE EXCEPTION 'Payment.amount (%) must equal listing.listed_price (%)', NEW.amount, l_listed_price;
  END IF;

  IF NEW.property_id <> l_listing_property_id THEN
    RAISE EXCEPTION 'Payment.property_id (%) must equal listing.property_id (%)', NEW.property_id, l_listing_property_id;
  END IF;

  RETURN NEW;
END;
$$;
SQL

echo "✅ Patched validate_payment_matches_listing() to support purchase reference_type"
