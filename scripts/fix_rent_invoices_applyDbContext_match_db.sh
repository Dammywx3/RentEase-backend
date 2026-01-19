#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILE="$ROOT/src/routes/rent_invoices.ts"

if [ ! -f "$FILE" ]; then
  echo "ERROR: $FILE not found"
  exit 1
fi

mkdir -p "$ROOT/scripts/.bak"
ts="$(date +%Y%m%d_%H%M%S)"
cp "$FILE" "$ROOT/scripts/.bak/rent_invoices.ts.bak.$ts"
echo "✅ backup -> scripts/.bak/rent_invoices.ts.bak.$ts"

perl -0777 -i -pe '
s{
async\s+function\s+applyDbContext\s*\(\s*client\s*:\s*any\s*,\s*req\s*:\s*any\s*\)\s*\{[\s\S]*?\n\}
}{
async function applyDbContext(client: any, req: any) {
  // Header is x-organization-id, but the DB setting key uses underscore: x_organization_id
  const orgId =
    req?.headers?.["x-organization-id"] ||
    req?.headers?.["X-Organization-Id"] ||
    req?.headers?.["x-organization-id".toLowerCase()];

  const userId = req?.user?.sub || "";
  const role = req?.user?.role || "";

  if (!orgId) {
    const e: any = new Error("Missing x-organization-id header");
    e.code = "ORG_ID_MISSING";
    throw e;
  }

  const org = String(orgId);
  const uid = userId ? String(userId) : "";
  const r = role ? String(role) : "";

  // ---- ORG context (MUST match current_organization_uuid()) ----
  await client.query("SELECT set_config('request.header.x_organization_id', $1, true);", [org]);
  await client.query("SELECT set_config('request.jwt.claim.org', $1, true);", [org]);
  await client.query("SELECT set_config('request.jwt.claims.org', $1, true);", [org]);
  await client.query("SELECT set_config('request.jwt.claim.organization_id', $1, true);", [org]);
  await client.query("SELECT set_config('app.organization_id', $1, true);", [org]);

  // (extra aliases harmless)
  await client.query("SELECT set_config('app.org_id', $1, true);", [org]);
  await client.query("SELECT set_config('rentease.organization_id', $1, true);", [org]);
  await client.query("SELECT set_config('rentease.org_id', $1, true);", [org]);

  // ---- USER context (commonly used by current_user_uuid()) ----
  await client.query("SELECT set_config('request.jwt.claim.sub', $1, true);", [uid]);
  await client.query("SELECT set_config('request.user_id', $1, true);", [uid]);
  await client.query("SELECT set_config('app.user_id', $1, true);", [uid]);
  await client.query("SELECT set_config('rentease.user_id', $1, true);", [uid]);

  await client.query("SELECT set_config('request.user_role', $1, true);", [r]);
  await client.query("SELECT set_config('app.user_role', $1, true);", [r]);
  await client.query("SELECT set_config('rentease.user_role', $1, true);", [r]);
}
}sx or die "Could not find applyDbContext(client:any, req:any) in $ARGV\n";
' "$FILE"

echo "✅ Patched applyDbContext() to set the exact keys current_organization_uuid() reads."
echo "➡️ Restart server: npm run dev"
