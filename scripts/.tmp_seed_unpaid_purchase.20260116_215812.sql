BEGIN;

WITH ins AS (
  INSERT INTO public.property_purchases(
    organization_id, property_id, listing_id,
    buyer_id, seller_id,
    agreed_price, currency,
    status, payment_status,
    created_at, updated_at
  ) VALUES (
    '1f297ca1-2764-4541-9d2e-00fe49e3d3bc'::uuid,
    '51f2e536-0a11-4923-9044-283f1d0ac26f'::uuid,
    'd307ee53-dc2a-495a-bc04-1d6b276e6175'::uuid,
    '69e26048-62aa-4e68-8deb-fb8bceb08885'::uuid,
    '69e26048-62aa-4e68-8deb-fb8bceb08885'::uuid,
    2000,
    'USD',
    'under_contract'::purchase_status,
    'unpaid'::purchase_payment_status,
    now(), now()
  )
  RETURNING id::text
)
SELECT id FROM ins;

COMMIT;
