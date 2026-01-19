BEGIN;

-- Ensure current_organization_uuid() can read org from multiple valid sources.
-- This avoids invalid GUC name like: request.header.x-organization-id
CREATE OR REPLACE FUNCTION public.current_organization_uuid()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(
    COALESCE(
      current_setting('request.jwt.claim.org', true),
      current_setting('request.jwt.claims.org', true),
      current_setting('request.jwt.claim.organization_id', true),
      current_setting('request.header.x_organization_id', true),
      current_setting('app.organization_id', true)
    ),
    ''
  )::uuid;
$$;

COMMIT;
