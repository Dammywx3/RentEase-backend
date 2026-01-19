
CREATE OR REPLACE FUNCTION public.validate_payment_matches_listing()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
  l_listed_price numeric(15,2);
  l_listing_property_id uuid;

  p_agreed_price numeric(15,2);
  p_currency varchar(3);
  p_property_id uuid;
  p_listing_id uuid;
  p_buyer_id uuid;

  -- rent invoice vars (NEW)
  ri_total numeric(15,2);
  ri_paid numeric(15,2);
  ri_currency varchar(3);
  ri_property_id uuid;
  ri_tenant_id uuid;
  ri_tenancy_id uuid;
  ri_listing_id uuid;

  ri_remaining numeric(15,2);
BEGIN
  -- =========================
  -- PURCHASE FLOW VALIDATION (existing)
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

    IF NEW.property_id <> p_property_id THEN
      RAISE EXCEPTION 'Payment.property_id (%) must equal purchase.property_id (%)', NEW.property_id, p_property_id;
    END IF;

    IF NEW.tenant_id <> p_buyer_id THEN
      RAISE EXCEPTION 'Payment.tenant_id (%) must equal purchase.buyer_id (%)', NEW.tenant_id, p_buyer_id;
    END IF;

    IF p_listing_id IS NOT NULL AND NEW.listing_id <> p_listing_id THEN
      RAISE EXCEPTION 'Payment.listing_id (%) must equal purchase.listing_id (%)', NEW.listing_id, p_listing_id;
    END IF;

    IF NEW.currency IS NULL THEN
      NEW.currency := p_currency;
    ELSIF NEW.currency <> p_currency THEN
      RAISE EXCEPTION 'Payment.currency (%) must equal purchase.currency (%)', NEW.currency, p_currency;
    END IF;

    RETURN NEW;
  END IF;

  -- =========================
  -- RENT INVOICE VALIDATION (NEW)
  -- =========================
  IF NEW.reference_type = 'rent_invoice' AND NEW.reference_id IS NOT NULL THEN
    -- join to tenancies to enforce listing_id (payments.listing_id is NOT NULL)
    SELECT
      ri.total_amount,
      ri.paid_amount,
      ri.currency,
      ri.property_id,
      ri.tenant_id,
      ri.tenancy_id,
      t.listing_id
    INTO
      ri_total,
      ri_paid,
      ri_currency,
      ri_property_id,
      ri_tenant_id,
      ri_tenancy_id,
      ri_listing_id
    FROM public.rent_invoices ri
    JOIN public.tenancies t ON t.id = ri.tenancy_id
    WHERE ri.id = NEW.reference_id
      AND ri.deleted_at IS NULL
    LIMIT 1;

    IF ri_property_id IS NULL THEN
      RAISE EXCEPTION 'Rent invoice not found for reference_id=%', NEW.reference_id;
    END IF;

    -- remaining balance (allows partial, blocks overpay)
    ri_remaining := (ri_total - COALESCE(ri_paid, 0));

    IF NEW.amount > ri_remaining THEN
      RAISE EXCEPTION 'Payment.amount (%) exceeds remaining invoice balance (%)', NEW.amount, ri_remaining;
    END IF;

    -- property + tenant must match invoice
    IF NEW.property_id <> ri_property_id THEN
      RAISE EXCEPTION 'Payment.property_id (%) must equal invoice.property_id (%)', NEW.property_id, ri_property_id;
    END IF;

    IF NEW.tenant_id <> ri_tenant_id THEN
      RAISE EXCEPTION 'Payment.tenant_id (%) must equal invoice.tenant_id (%)', NEW.tenant_id, ri_tenant_id;
    END IF;

    -- enforce listing_id from tenancy (best/strict)
    IF ri_listing_id IS NULL THEN
      RAISE EXCEPTION 'Tenancy (%) has NULL listing_id. Cannot create payments row because payments.listing_id is required.', ri_tenancy_id;
    END IF;

    IF NEW.listing_id <> ri_listing_id THEN
      RAISE EXCEPTION 'Payment.listing_id (%) must equal tenancy.listing_id (%) for invoice payments', NEW.listing_id, ri_listing_id;
    END IF;

    -- currency: default to invoice currency if not provided; otherwise must match
    IF NEW.currency IS NULL THEN
      NEW.currency := ri_currency;
    ELSIF NEW.currency <> ri_currency THEN
      RAISE EXCEPTION 'Payment.currency (%) must equal invoice.currency (%)', NEW.currency, ri_currency;
    END IF;

    RETURN NEW;
  END IF;

  -- =========================
  -- DEFAULT LISTING VALIDATION (existing)
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
$function$;