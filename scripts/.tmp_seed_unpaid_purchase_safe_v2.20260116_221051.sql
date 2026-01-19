BEGIN;

-- 1) Find a property+listing that does NOT already have an open purchase
--    (This avoids uniq_open_purchase_per_property collisions.)
WITH candidate AS (
  SELECT
    p.id::uuid  AS property_id,
    l.id::uuid  AS listing_id
  FROM public.properties p
  JOIN public.property_listings l
    ON l.organization_id = p.organization_id
   AND l.property_id = p.id
   AND l.deleted_at IS NULL
  WHERE p.organization_id = '1f297ca1-2764-4541-9d2e-00fe49e3d3bc'::uuid
    AND p.deleted_at IS NULL
    AND NOT EXISTS (
      SELECT 1
      FROM public.property_purchases pp
      WHERE pp.organization_id = p.organization_id
        AND pp.property_id = p.id
        AND pp.deleted_at IS NULL
        -- treat these as "still open" (adjust if your unique index is different)
        AND pp.status::text NOT IN ('cancelled','refunded','closed')
    )
  ORDER BY p.created_at DESC
  LIMIT 1
),

ins AS (
  INSERT INTO public.property_purchases(
    organization_id, property_id, listing_id,
    buyer_id, seller_id,
    agreed_price, currency,
    status, payment_status,
    created_at, updated_at
  )
  SELECT
    '1f297ca1-2764-4541-9d2e-00fe49e3d3bc'::uuid,
    c.property_id,
    c.listing_id,
    '69e26048-62aa-4e68-8deb-fb8bceb08885'::uuid,
    '69e26048-62aa-4e68-8deb-fb8bceb08885'::uuid,
    2000,
    'USD',
    'under_contract'::purchase_status,
    'unpaid'::purchase_payment_status,
    now(), now()
  FROM candidate c
  RETURNING id::text
),

fallback AS (
  -- 2) If no candidate property exists, reuse latest existing open purchase instead of failing.
  SELECT pp.id::text AS id
  FROM public.property_purchases pp
  WHERE pp.organization_id = '1f297ca1-2764-4541-9d2e-00fe49e3d3bc'::uuid
    AND pp.deleted_at IS NULL
    AND pp.status::text NOT IN ('cancelled','refunded','closed')
  ORDER BY pp.created_at DESC
  LIMIT 1
)

SELECT id FROM ins
UNION ALL
SELECT id FROM fallback
LIMIT 1;

COMMIT;
