BEGIN;

-- Make sure RLS is enabled (it is in your schema, but safe)
ALTER TABLE public.invoice_payments ENABLE ROW LEVEL SECURITY;

-- Drop old insert policy if it exists (name based on your \d+ output)
DROP POLICY IF EXISTS invoice_payments_write_insert ON public.invoice_payments;

-- Recreate insert policy:
-- Allow:
--   - admin
--   - rentease_service DB role
--   - tenant who owns BOTH the invoice and the payment
CREATE POLICY invoice_payments_write_insert
ON public.invoice_payments
FOR INSERT
WITH CHECK (
  organization_id = current_organization_uuid()
  AND (
    is_admin()
    OR (CURRENT_USER = 'rentease_service'::name)
    OR EXISTS (
      SELECT 1
      FROM public.rent_invoices ri
      JOIN public.payments p
        ON p.id = invoice_payments.payment_id
      WHERE ri.id = invoice_payments.invoice_id
        AND ri.deleted_at IS NULL
        AND ri.organization_id = current_organization_uuid()
        AND ri.tenant_id = current_user_uuid()
        AND p.deleted_at IS NULL
        AND p.tenant_id = current_user_uuid()
    )
  )
);

COMMIT;
