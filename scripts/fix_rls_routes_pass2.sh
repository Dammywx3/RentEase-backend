#!/usr/bin/env bash
set -euo pipefail

STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="scripts/_backup_rls_fix_pass2_${STAMP}"
mkdir -p "$BACKUP_DIR"

FILES=(
  "src/db/set_pg_context.ts"
  "src/routes/payments.ts"
  "src/routes/purchase_escrow.ts"
  "src/routes/rent_invoices.ts"
)

echo "============================================================"
echo "RentEase: RLS Fix Pass #2 (Centralize set_config -> setPgContext)"
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
# 1) Replace src/db/set_pg_context.ts with a FULL SAFE implementation
# ------------------------------------------------------------
cat > src/db/set_pg_context.ts <<'TS'
import type { PoolClient } from "pg";

export type PgContextlBool = boolean;

export type PgContextOpts = {
  userId?: string | null;
  organizationId?: string | null;
  role?: string | null;
  eventNote?: string | null;
};

/**
 * Centralized RLS/session context setter.
 *
 * Uses SET LOCAL (is_local=true) so values are scoped to the current transaction
 * when called after BEGIN. This prevents pool leakage.
 *
 * We set multiple aliases because different parts of the app / policies / triggers
 * may reference different keys.
 */
export async function setPgContext(client: PoolClient, opts: PgContextOpts) {
  const userId = String(opts.userId ?? "").trim();
  const organizationId = String(opts.organizationId ?? "").trim();
  const role = String(opts.role ?? "").trim();
  const eventNote = String(opts.eventNote ?? "").trim();

  // Helper for SET LOCAL
  async function setKey(key: string, value: string) {
    // must be called inside transaction if you want LOCAL behavior
    await client.query("SELECT set_config($1, $2, true);", [key, value]);
  }

  // --- Org keys
  if (organizationId) {
    await setKey("app.organization_id", organizationId);
    await setKey("app.current_organization", organizationId);
    await setKey("request.header.x_organization_id", organizationId);
    await setKey("rentease.organization_id", organizationId);
  } else {
    // keep keys predictable if someone checks existence
    await setKey("app.organization_id", "");
    await setKey("app.current_organization", "");
    await setKey("request.header.x_organization_id", "");
    await setKey("rentease.organization_id", "");
  }

  // --- User keys
  if (userId) {
    await setKey("app.user_id", userId);
    await setKey("app.current_user", userId);
    await setKey("request.jwt.claim.sub", userId);
    await setKey("rentease.user_id", userId);
  } else {
    await setKey("app.user_id", "");
    await setKey("app.current_user", "");
    await setKey("request.jwt.claim.sub", "");
    await setKey("rentease.user_id", "");
  }

  // --- Role keys (some policies/triggers may read these)
  if (role) {
    await setKey("request.user_role", role);
    await setKey("app.user_role", role);
    await setKey("rentease.user_role", role);
  } else {
    await setKey("request.user_role", "");
    await setKey("app.user_role", "");
    await setKey("rentease.user_role", "");
  }

  // --- Optional event note (good for audit/debug)
  if (eventNote) {
    // Avoid super long config values
    const clean = eventNote.slice(0, 200);
    await setKey("app.event_note", clean);
    await setKey("rentease.event_note", clean);
  } else {
    await setKey("app.event_note", "");
    await setKey("rentease.event_note", "");
  }
}
TS

echo "✅ Wrote FULL src/db/set_pg_context.ts"

# ------------------------------------------------------------
# 2) payments.ts: replace the 4-line manual set_config block with setPgContext
# ------------------------------------------------------------
if [[ -f "src/routes/payments.ts" ]]; then
  perl -0777 -i -pe '
    s/\Qawait client.query("select set_config('\''app.organization_id'\'', $1, true)", [organizationId]);\E\s*\n
      \Qawait client.query("select set_config('\''request.header.x_organization_id'\'', $1, true)", [organizationId]);\E\s*\n
      \Qawait client.query("select set_config('\''request.jwt.claim.sub'\'', $1, true)", [userId]);\E\s*\n
      \Qawait client.query("select set_config('\''app.user_id'\'', $1, true)", [userId]);\E
    /await setPgContext(client, { userId, organizationId, role: String(req.user?.role ?? \"\").trim() || null, eventNote: \"payments:tx\" });/gsx
  ' src/routes/payments.ts

  # Ensure import exists
  if ! rg -n 'from "\.\./db/set_pg_context\.js"' src/routes/payments.ts >/dev/null 2>&1; then
    perl -0777 -i -pe '
      s/(import[^\n]*\n)+/sprintf("%s\n", $&)/e;
    ' src/routes/payments.ts
    # insert after first import block line
    perl -i -pe '
      if ($.==1) { }
    ' src/routes/payments.ts
    # safer: add near top after imports using perl
    perl -0777 -i -pe '
      s/(import[^\n]*\n)(?!.*setPgContext)/$1import { setPgContext } from "..\/db\/set_pg_context.js";\n/s
    ' src/routes/payments.ts
  fi

  echo "✅ Patched src/routes/payments.ts set_config -> setPgContext"
fi

# ------------------------------------------------------------
# 3) purchase_escrow.ts: replace set_config block with setPgContext
# ------------------------------------------------------------
if [[ -f "src/routes/purchase_escrow.ts" ]]; then
  perl -0777 -i -pe '
    s/\Qawait client.query("select set_config('\''app.organization_id'\'', $1, true)", [organizationId]);\E\s*\n
      \Qawait client.query("select set_config('\''request.header.x_organization_id'\'', $1, true)", [organizationId]);\E\s*\n
      \Qawait client.query("select set_config('\''request.jwt.claim.sub'\'', $1, true)", [userId]);\E\s*\n
      \Qawait client.query("select set_config('\''app.user_id'\'', $1, true)", [userId]);\E
    /await setPgContext(client, { userId, organizationId, role: String(req.user?.role ?? \"\").trim() || null, eventNote: \"purchase:escrow\" });/gsx
  ' src/routes/purchase_escrow.ts

  if ! rg -n 'from "\.\./db/set_pg_context\.js"' src/routes/purchase_escrow.ts >/dev/null 2>&1; then
    perl -0777 -i -pe '
      s/(import[^\n]*\n)(?!.*setPgContext)/$1import { setPgContext } from "..\/db\/set_pg_context.js";\n/s
    ' src/routes/purchase_escrow.ts
  fi

  echo "✅ Patched src/routes/purchase_escrow.ts set_config -> setPgContext"
fi

# ------------------------------------------------------------
# 4) rent_invoices.ts: replace SELECT set_config(...) block with setPgContext
# ------------------------------------------------------------
if [[ -f "src/routes/rent_invoices.ts" ]]; then
  # Replace the contiguous block setting org/user/role keys
  perl -0777 -i -pe '
    s/await client\.query\("SELECT set_config\(\x27request\.header\.x_organization_id\x27, \$1, true\);\x22,\s*\[orgId\]\);\s*
      await client\.query\("SELECT set_config\(\x27app\.organization_id\x27, \$1, true\);\x22,\s*\[orgId\]\);\s*
      (?:\s*\n)?\s*
      await client\.query\("SELECT set_config\(\x27request\.jwt\.claim\.sub\x27, \$1, true\);\x22,\s*\[userId\]\);\s*
      await client\.query\("SELECT set_config\(\x27app\.user_id\x27, \$1, true\);\x22,\s*\[userId\]\);\s*
      (?:\s*\n)?\s*
      await client\.query\("SELECT set_config\(\x27request\.user_role\x27, \$1, true\);\x22,\s*\[role\]\);\s*
      await client\.query\("SELECT set_config\(\x27app\.user_role\x27, \$1, true\);\x22,\s*\[role\]\);\s*
      await client\.query\("SELECT set_config\(\x27rentease\.user_role\x27, \$1, true\);\x22,\s*\[role\]\);\s*
    /await setPgContext(client, { userId, organizationId: orgId, role, eventNote: \"rent_invoices\" });\n/gsx
  ' src/routes/rent_invoices.ts

  if ! rg -n 'from "\.\./db/set_pg_context\.js"' src/routes/rent_invoices.ts >/dev/null 2>&1; then
    perl -0777 -i -pe '
      s/(import[^\n]*\n)(?!.*setPgContext)/$1import { setPgContext } from "..\/db\/set_pg_context.js";\n/s
    ' src/routes/rent_invoices.ts
  fi

  echo "✅ Patched src/routes/rent_invoices.ts set_config -> setPgContext"
fi

echo "============================================================"
echo "✅ PASS #2 DONE"
echo "Backup: $BACKUP_DIR"
echo ""
echo "Now run:"
echo "  npm run build"
echo "  rg -n \"set_config\\(\" src/routes src/services | rg -v \"set_pg_context\" || true"
echo "============================================================"
