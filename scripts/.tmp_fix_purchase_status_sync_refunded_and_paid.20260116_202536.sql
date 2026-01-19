BEGIN;

-- 1) If money got refunded, status must be refunded (per your desired flow)
UPDATE public.property_purchases
SET status = 'refunded',
    updated_at = now()
WHERE deleted_at IS NULL
  AND payment_status::text = 'refunded'
  AND status::text <> 'refunded';

-- 2) If money got paid and you want status reflect it, set status=paid
UPDATE public.property_purchases
SET status = 'paid',
    updated_at = now()
WHERE deleted_at IS NULL
  AND payment_status::text = 'paid'
  AND status::text = 'under_contract';

COMMIT;

-- Report after
SELECT status::text as status, payment_status::text as payment_status, count(*) as cnt
FROM public.property_purchases
WHERE deleted_at IS NULL
GROUP BY 1,2
ORDER BY 3 DESC;
