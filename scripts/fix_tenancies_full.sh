#!/usr/bin/env bash
set -euo pipefail

mkdir -p scripts

# -------------------------------------------------------------------
# 1) Rewrite src/routes/tenancies.ts (NO req.rls dependency)
# -------------------------------------------------------------------
cat > src/routes/tenancies.ts <<'TS'
import type { FastifyInstance } from "fastify";

import { withRlsTransaction } from "../db.js";
import { createTenancyBodySchema, listTenanciesQuerySchema } from "../schemas/tenancies.schema.js";
import { createTenancy, getTenancies } from "../services/tenancies.service.js";

function getRlsCtx(req: any): { userId: string; organizationId: string } {
  // If your app sets req.rls, use it
  const rls = req?.rls;
  if (rls?.userId && rls?.organizationId) {
    return { userId: String(rls.userId), organizationId: String(rls.organizationId) };
  }

  const user = req?.user;

  // Common places Fastify auth puts user id
  const userId =
    user?.id ??
    user?.userId ??
    user?.sub ??
    req?.auth?.userId ??
    req?.auth?.sub;

  // Org id: prefer header, fallback to user payload if present
  const hdr =
    req?.headers?.["x-organization-id"] ??
    req?.headers?.["x-org-id"] ??
    req?.headers?.["x-organizationid"];

  const userOrg =
    user?.organization_id ??
    user?.organizationId ??
    user?.org_id ??
    user?.orgId;

  const organizationId = hdr ?? userOrg;

  if (!userId || !organizationId) {
    throw new Error(
      `Missing RLS ctx. userId=${String(userId ?? "")} organizationId=${String(organizationId ?? "")}. ` +
      `Pass header x-organization-id OR ensure auth sets req.rls.`
    );
  }

  return { userId: String(userId), organizationId: String(organizationId) };
}

export async function tenancyRoutes(app: FastifyInstance) {
  app.get("/v1/tenancies", { preHandler: [app.authenticate] }, async (req) => {
    const q = listTenanciesQuerySchema.parse((req as any).query ?? {});
    const ctx = getRlsCtx(req);

    const data = await withRlsTransaction(ctx, (client) =>
      getTenancies(client, {
        limit: q.limit,
        offset: q.offset,
        tenantId: q.tenantId,
        propertyId: q.propertyId,
        listingId: q.listingId,
        status: q.status as any,
      })
    );

    return { ok: true, data, paging: { limit: q.limit, offset: q.offset } };
  });

  app.post("/v1/tenancies", { preHandler: [app.authenticate] }, async (req) => {
    const body = createTenancyBodySchema.parse((req as any).body ?? {});
    const ctx = getRlsCtx(req);

    const data = await withRlsTransaction(ctx, (client) =>
      createTenancy(client, {
        tenantId: body.tenantId,
        propertyId: body.propertyId,
        listingId: body.listingId ?? null,

        rentAmount: body.rentAmount,
        securityDeposit: body.securityDeposit ?? null,

        startDate: body.startDate,
        nextDueDate: body.nextDueDate,

        paymentCycle: (body.paymentCycle as any) ?? null,
        status: (body.status as any) ?? null,

        terminationReason: body.terminationReason ?? null,
      })
    );

    return { ok: true, data };
  });
}
TS

# -------------------------------------------------------------------
# 2) Rewrite scripts/test_tenancies.sh (always sends x-organization-id)
# -------------------------------------------------------------------
cat > scripts/test_tenancies.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail

API="${API:-http://127.0.0.1:4000}"
DB_NAME="${DB_NAME:-rentease}"

eval "$(./scripts/login.sh)"
echo "✅ TOKEN set"

ME_JSON="$(curl -s "$API/v1/me" -H "authorization: Bearer $TOKEN")"

ME_ID="$(echo "$ME_JSON" | jq -r '.data.id')"
ORG_ID="$(echo "$ME_JSON" | jq -r '.data.organization_id // .data.organizationId // .data.org_id // .data.orgId // empty')"

if [ -z "${ORG_ID:-}" ] || [ "$ORG_ID" = "null" ]; then
  echo "❌ ORG_ID not found in /v1/me response. Here is /v1/me:"
  echo "$ME_JSON" | jq
  exit 1
fi

PROPERTY_ID="$(curl -s "$API/v1/properties?limit=1&offset=0" -H "authorization: Bearer $TOKEN" | jq -r '.data[0].id')"
LISTING_ID="$(curl -s "$API/v1/listings?limit=1&offset=0" -H "authorization: Bearer $TOKEN" | jq -r '.data[0].id')"

echo "ME_ID=$ME_ID"
echo "ORG_ID=$ORG_ID"
echo "PROPERTY_ID=$PROPERTY_ID"
echo "LISTING_ID=$LISTING_ID"

echo
echo "Creating tenancy..."
curl -s -X POST "$API/v1/tenancies" \
  -H "content-type: application/json" \
  -H "authorization: Bearer $TOKEN" \
  -H "x-organization-id: $ORG_ID" \
  -d "{
    \"listingId\":\"$LISTING_ID\",
    \"propertyId\":\"$PROPERTY_ID\",
    \"tenantId\":\"$ME_ID\",
    \"startDate\":\"2026-02-01\",
    \"nextDueDate\":\"2026-03-01\",
    \"rentAmount\":2000,
    \"securityDeposit\":500,
    \"status\":\"pending_start\"
  }" | jq

echo
echo "Listing tenancies..."
curl -s "$API/v1/tenancies?limit=10&offset=0" \
  -H "authorization: Bearer $TOKEN" \
  -H "x-organization-id: $ORG_ID" | jq

echo
echo "DB check: tenancies (last 5)"
PAGER=cat psql -d "$DB_NAME" -c "select id, tenant_id, property_id, listing_id, status, start_date, next_due_date, rent_amount, security_deposit, created_at from tenancies order by created_at desc limit 5;"
SH
chmod +x scripts/test_tenancies.sh

# -------------------------------------------------------------------
# 3) Clean duplicate route registration in src/routes/index.ts (keep first)
# -------------------------------------------------------------------
if [ -f src/routes/index.ts ]; then
  awk '
    {
      if ($0 ~ /await[[:space:]]+app\.register\(tenancyRoutes\);/) {
        if (seen++) next
      }
      print
    }
  ' src/routes/index.ts > /tmp/index.ts && mv /tmp/index.ts src/routes/index.ts
fi

echo "✅ Done:"
echo "  - Rewrote src/routes/tenancies.ts (ctx fallback: req.rls OR header+req.user)"
echo "  - Rewrote scripts/test_tenancies.sh (sends x-organization-id)"
echo "  - Cleaned duplicate tenancyRoutes registration in src/routes/index.ts"
echo
echo "Next commands:"
echo "  bash -lc 'kill -9 \$(lsof -t -iTCP:4000 -sTCP:LISTEN) 2>/dev/null || true'"
echo "  npm run dev"
echo "  ./scripts/test_tenancies.sh"
