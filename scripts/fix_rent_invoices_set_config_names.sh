#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILE="$ROOT/src/routes/rent_invoices.ts"

mkdir -p "$ROOT/scripts/.bak"
ts="$(date +%Y%m%d_%H%M%S)"
cp "$FILE" "$ROOT/scripts/.bak/rent_invoices.ts.bak.$ts"
echo "✅ backup -> scripts/.bak/rent_invoices.ts.bak.$ts"

perl -0777 -i -pe '
  s{
    async\s+function\s+applyDbContext\([\s\S]*?\n\}
  }{
async function applyDbContext(client: any, req: any) {
  const orgId =
    req?.headers?.["x-organization-id"] ||
    req?.headers?.["X-Organization-Id"] ||
    req?.headers?.["x-organization-id".toLowerCase()];

  const userId = req?.user?.sub || null;
  const role = req?.user?.role || null;

  if (!orgId) {
    const e: any = new Error("Missing x-organization-id header");
    e.code = "ORG_ID_MISSING";
    throw e;
  }

  // IMPORTANT:
  // Postgres custom GUC names:
  // - MUST contain a dot
  // - MUST NOT contain dashes (-)
  await client.query(
    `
    SELECT
      set_config('request.organization_id', $1, true),
      set_config('request.org_id', $1, true),
      set_config('app.organization_id', $1, true),
      set_config('app.org_id', $1, true),
      set_config('rentease.organization_id', $1, true),
      set_config('rentease.org_id', $1, true),

      set_config('request.user_id', COALESCE($2,''), true),
      set_config('app.user_id', COALESCE($2,''), true),
      set_config('rentease.user_id', COALESCE($2,''), true),
      set_config('request.jwt.claim.sub', COALESCE($2,''), true),

      set_config('request.user_role', COALESCE($3,''), true),
      set_config('app.user_role', COALESCE($3,''), true),
      set_config('rentease.user_role', COALESCE($3,''), true);
    `,
    [String(orgId), userId ? String(userId) : "", role ? String(role) : ""]
  );
}
}sx or die "Could not find applyDbContext() in $ARGV\n";
' "$FILE"

echo "✅ Patched applyDbContext() set_config names"
echo "➡️ Restart: npm run dev"
