#!/usr/bin/env bash
set -euo pipefail

# 0) Ensure comments work if user runs chunks in zsh later (not needed for this script)
#    (this script is bash)

# 1) Clean duplicate tenancyRoutes registrations (keep first)
if [ -f src/routes/index.ts ]; then
  perl -i -pe 'BEGIN{$seen=0} if(/^\s*await\s+app\.register\(tenancyRoutes\);\s*$/){ if($seen++){ $_="" } }' src/routes/index.ts
fi

# 2) Rewrite src/routes/tenancies.ts to build ctx even if req.rls is missing
cat > src/routes/tenancies.ts <<'TS'
import type { FastifyInstance } from "fastify";

import { withRlsTransaction } from "../db.js";
import { createTenancyBodySchema, listTenanciesQuerySchema } from "../schemas/tenancies.schema.js";
import { createTenancy, getTenancies } from "../services/tenancies.service.js";

// Build RLS ctx robustly.
// - Prefer req.rls if your auth plugin sets it.
// - Otherwise derive from req.user + header.
function getRlsCtx(req: any): { userId: string; organizationId: string } {
  const fromRls = req?.rls;
  if (fromRls?.userId && fromRls?.organizationId) {
    return { userId: String(fromRls.userId), organizationId: String(fromRls.organizationId) };
  }

  const user = req?.user;

  // common places auth plugins put user id
  const userId =
    user?.id ??
    user?.userId ??
    user?.sub ??
    req?.auth?.userId ??
    req?.auth?.sub;

  // common places org id might exist
  const headerOrg =
    req?.headers?.["x-organization-id"] ??
    req?.headers?.["x-org-id"] ??
    req?.headers?.["x-organizationid"];

  const userOrg =
    user?.organization_id ??
    user?.organizationId ??
    user?.org_id ??
    user?.orgId;

  const organizationId = headerOrg ?? userOrg;

  if (!userId || !organizationId) {
    // This will show up as INTERNAL_ERROR in your current error handler,
    // but the message will now be clear about what is missing.
    throw new Error(
      `Missing RLS context: userId=${String(userId ?? "")} organizationId=${String(organizationId ?? "")}. ` +
      `Ensure auth sets req.rls OR pass x-organization-id header.`
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

# 3) Patch scripts/test_tenancies.sh to send x-organization-id
#    (fetch ORG_ID from /v1/me using multiple possible field names)
if [ -f scripts/test_tenancies.sh ]; then
  perl -0777 -pi -e 's/ME_ID="\$\((?:.|\n)*?\.data\.id(?:.|\n)*?\)"/ME_ID="\$\((curl -s \$API\\/v1\\/me -H \"authorization: Bearer \$TOKEN\" | jq -r \x27.data.id\x27)\)\"\nORG_ID=\"\$\((curl -s \$API\\/v1\\/me -H \"authorization: Bearer \$TOKEN\" | jq -r \x27.data.organization_id \\/\\/ .data.organizationId \\/\\/ .data.org_id \\/\\/ .data.orgId \\/\\/ empty\x27)\)\"/m' scripts/test_tenancies.sh

  # If ORG_ID line didn’t inject (different formatting), insert after ME_ID line
  if ! grep -q '^ORG_ID=' scripts/test_tenancies.sh; then
    perl -pi -e 'if(/^ME_ID=/){ print; print "ORG_ID=\"\$(curl -s \$API\\/v1\\/me -H \\\"authorization: Bearer \\$TOKEN\\\" | jq -r \x27.data.organization_id \\/\\/ .data.organizationId \\/\\/ .data.org_id \\/\\/ .data.orgId \\/\\/ empty\x27)\"\n"; next }' scripts/test_tenancies.sh
  fi

  # Add echo for ORG_ID (after ME_ID print)
  if ! grep -q 'echo "ORG_ID=' scripts/test_tenancies.sh; then
    perl -pi -e 'if(/^echo "ME_ID=/){ print; print "echo \"ORG_ID=\$ORG_ID\"\n"; next }' scripts/test_tenancies.sh
  fi

  # Add header to POST and GET calls if missing
  perl -pi -e 's/-H "authorization: Bearer \$TOKEN"/-H "authorization: Bearer \$TOKEN"\n  -H "x-organization-id: \$ORG_ID"/g' scripts/test_tenancies.sh
fi

echo "✅ Fixed: tenancies routes now build RLS ctx (req.rls OR req.user + x-organization-id)."
echo "✅ Fixed: scripts/test_tenancies.sh now sends x-organization-id."
echo "✅ Cleaned: src/routes/index.ts (tenancyRoutes registered once)."
echo
echo "Next:"
echo "  bash -lc 'kill -9 \$(lsof -t -iTCP:4000 -sTCP:LISTEN) 2>/dev/null || true'"
echo "  npm run dev"
echo "  ./scripts/test_tenancies.sh"
