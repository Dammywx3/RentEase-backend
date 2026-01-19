#!/usr/bin/env bash
set -euo pipefail

STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="scripts/_backup_rls_fix_pass3_${STAMP}"
mkdir -p "$BACKUP_DIR"

FILES=(
  "src/db/set_pg_context.ts"
  "src/services/purchase_escrow.service.ts"
  "src/services/rent_invoice_payments.service.ts"
)

echo "============================================================"
echo "RentEase: RLS Fix Pass #3 (Services: set_config -> setPgContext, SAFE partial)"
echo "Backup dir: $BACKUP_DIR"
echo "============================================================"

# Backup
for f in "${FILES[@]}"; do
  if [[ -f "$f" ]]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$f")"
    cp "$f" "$BACKUP_DIR/$f"
  fi
done
echo "✅ Backed up target files."

# ------------------------------------------------------------
# 1) Make setPgContext PARTIAL: only set keys that are provided (do NOT blank others)
# ------------------------------------------------------------
if [[ -f "src/db/set_pg_context.ts" ]]; then
  cat > src/db/set_pg_context.ts <<'TS'
import type { PoolClient } from "pg";

/**
 * PgContextOpts (PARTIAL / SAFE)
 * - Only sets keys you provide (does NOT overwrite others with empty strings).
 * - Uses set_config(..., true) which is LOCAL to the current transaction when called after BEGIN.
 */
export type PgContextOpts = {
  userId?: string | null;
  organizationId?: string | null;
  role?: string | null;
  eventNote?: string | null;
};

function clean(v: unknown): string | null {
  const s = String(v ?? "").trim();
  return s ? s : null;
}

async function setLocal(client: PoolClient, key: string, value: string) {
  // LOCAL to tx if called after BEGIN
  await client.query("SELECT set_config($1, $2, true)", [key, value]);
}

export async function setPgContext(client: PoolClient, opts: PgContextOpts) {
  const userId = clean(opts.userId);
  const organizationId = clean(opts.organizationId);
  const role = clean(opts.role);
  const eventNote = clean(opts.eventNote);

  // ---- Organization (set all aliases your policies might use) ----
  if (organizationId) {
    await setLocal(client, "request.header.x_organization_id", organizationId);
    await setLocal(client, "app.organization_id", organizationId);
    await setLocal(client, "app.current_organization", organizationId);
    await setLocal(client, "app.current_organization_id", organizationId);
  }

  // ---- User ----
  if (userId) {
    await setLocal(client, "request.jwt.claim.sub", userId);
    await setLocal(client, "app.user_id", userId);
    await setLocal(client, "app.current_user", userId);
    await setLocal(client, "app.current_user_id", userId);
  }

  // ---- Role ----
  if (role) {
    await setLocal(client, "request.user_role", role);
    await setLocal(client, "app.user_role", role);
    await setLocal(client, "rentease.user_role", role);
  }

  // ---- Event note (optional, only if provided) ----
  if (eventNote) {
    await setLocal(client, "app.event_note", eventNote);
  }
}

export default setPgContext;
TS

  echo "✅ Rewrote src/db/set_pg_context.ts (SAFE partial updates)"
fi

ensure_service_import () {
  local file="$1"
  # Add import only if missing
  if ! rg -n 'from "\.\./db/set_pg_context\.js"' "$file" >/dev/null 2>&1; then
    perl -0777 -i -pe 's/(import[^\n]*\n)/$1import { setPgContext } from "..\/db\/set_pg_context.js";\n/s' "$file"
  fi
}

# ------------------------------------------------------------
# 2) purchase_escrow.service.ts: set_config('app.organization_id'...) -> setPgContext({organizationId: ...})
# ------------------------------------------------------------
if [[ -f "src/services/purchase_escrow.service.ts" ]]; then
  ensure_service_import "src/services/purchase_escrow.service.ts"

  perl -0777 -i -pe '
    s/await\s+client\.query\("select\s+set_config\(\x27app\.organization_id\x27,\s*\$1,\s*true\)"\s*,\s*\[row\.organization_id\]\);\s*/
await setPgContext(client, { organizationId: row.organization_id, eventNote: "purchase_escrow:service" });\n/s
  ' src/services/purchase_escrow.service.ts

  echo "✅ Patched src/services/purchase_escrow.service.ts"
fi

# ------------------------------------------------------------
# 3) rent_invoice_payments.service.ts: set_config('app.organization_id'...) -> setPgContext({organizationId: ...})
# ------------------------------------------------------------
if [[ -f "src/services/rent_invoice_payments.service.ts" ]]; then
  ensure_service_import "src/services/rent_invoice_payments.service.ts"

  perl -0777 -i -pe '
    s/await\s+client\.query\("select\s+set_config\(\x27app\.organization_id\x27,\s*\$1,\s*true\)"\s*,\s*\[orgId\]\);\s*/
await setPgContext(client, { organizationId: orgId, eventNote: "rent_invoice_payments:service" });\n/s
  ' src/services/rent_invoice_payments.service.ts

  echo "✅ Patched src/services/rent_invoice_payments.service.ts"
fi

echo "============================================================"
echo "✅ PASS #3 DONE"
echo "Backup: $BACKUP_DIR"
echo ""
echo "Now run:"
echo "  npm run build"
echo "  rg -n \"set_config\\(\" -g'!*.bak*' src/routes src/services | rg -v \"set_pg_context\" || true"
echo "============================================================"
