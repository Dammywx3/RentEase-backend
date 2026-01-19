#!/usr/bin/env bash
set -euo pipefail

STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="scripts/_backup_rls_fix_pass2_1_${STAMP}"
mkdir -p "$BACKUP_DIR"

FILES=(
  "src/routes/payments.ts"
  "src/routes/purchase_escrow.ts"
  "src/routes/rent_invoices.ts"
)

echo "============================================================"
echo "RentEase: RLS Fix Pass #2.1 (Force replace remaining set_config blocks in routes)"
echo "Backup dir: $BACKUP_DIR"
echo "============================================================"

# Backup
for f in "${FILES[@]}"; do
  if [[ -f "$f" ]]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$f")"
    cp "$f" "$BACKUP_DIR/$f"
  fi
done
echo "✅ Backed up target route files."

ensure_import () {
  local file="$1"
  # Add import only if missing
  if ! rg -n 'from "\.\./db/set_pg_context\.js"' "$file" >/dev/null 2>&1; then
    perl -0777 -i -pe 's/(import[^\n]*\n)/$1import { setPgContext } from "..\/db\/set_pg_context.js";\n/s' "$file"
  fi
}

# ------------------------------------------------------------
# payments.ts: replace BOTH blocks of 4 set_config lines with setPgContext(...)
# ------------------------------------------------------------
if [[ -f "src/routes/payments.ts" ]]; then
  ensure_import "src/routes/payments.ts"

  perl -0777 -i -pe '
    s/\s*await\s+client\.query\("select\s+set_config\(\x27app\.organization_id\x27,\s*\$1,\s*true\)"\s*,\s*\[organizationId\]\);\s*
      await\s+client\.query\("select\s+set_config\(\x27request\.header\.x_organization_id\x27,\s*\$1,\s*true\)"\s*,\s*\[organizationId\]\);\s*
      await\s+client\.query\("select\s+set_config\(\x27request\.jwt\.claim\.sub\x27,\s*\$1,\s*true\)"\s*,\s*\[userId\]\);\s*
      await\s+client\.query\("select\s+set_config\(\x27app\.user_id\x27,\s*\$1,\s*true\)"\s*,\s*\[userId\]\);\s*
    /\n        await setPgContext(client, { userId, organizationId, role: String(req.user?.role ?? \"\").trim() || null, eventNote: \"payments\" });\n/sxg
  ' src/routes/payments.ts

  echo "✅ Fixed src/routes/payments.ts (set_config -> setPgContext)"
fi

# ------------------------------------------------------------
# purchase_escrow.ts: replace the 4 set_config lines with setPgContext(...)
# ------------------------------------------------------------
if [[ -f "src/routes/purchase_escrow.ts" ]]; then
  ensure_import "src/routes/purchase_escrow.ts"

  perl -0777 -i -pe '
    s/\s*await\s+client\.query\("select\s+set_config\(\x27app\.organization_id\x27,\s*\$1,\s*true\)"\s*,\s*\[organizationId\]\);\s*
      await\s+client\.query\("select\s+set_config\(\x27request\.header\.x_organization_id\x27,\s*\$1,\s*true\)"\s*,\s*\[organizationId\]\);\s*
      await\s+client\.query\("select\s+set_config\(\x27request\.jwt\.claim\.sub\x27,\s*\$1,\s*true\)"\s*,\s*\[userId\]\);\s*
      await\s+client\.query\("select\s+set_config\(\x27app\.user_id\x27,\s*\$1,\s*true\)"\s*,\s*\[userId\]\);\s*
    /\n        await setPgContext(client, { userId, organizationId, role: String(req.user?.role ?? \"\").trim() || null, eventNote: \"purchase_escrow\" });\n/sxg
  ' src/routes/purchase_escrow.ts

  echo "✅ Fixed src/routes/purchase_escrow.ts (set_config -> setPgContext)"
fi

# ------------------------------------------------------------
# rent_invoices.ts: replace the big SELECT set_config(...) block with setPgContext(...)
# ------------------------------------------------------------
if [[ -f "src/routes/rent_invoices.ts" ]]; then
  ensure_import "src/routes/rent_invoices.ts"

  perl -0777 -i -pe '
    s/\s*await\s+client\.query\("SELECT\s+set_config\(\x27request\.header\.x_organization_id\x27,\s*\$1,\s*true\);\x22\s*,\s*\[orgId\]\);\s*
      await\s+client\.query\("SELECT\s+set_config\(\x27app\.organization_id\x27,\s*\$1,\s*true\);\x22\s*,\s*\[orgId\]\);\s*
      (?:\s*\n)?\s*
      await\s+client\.query\("SELECT\s+set_config\(\x27request\.jwt\.claim\.sub\x27,\s*\$1,\s*true\);\x22\s*,\s*\[userId\]\);\s*
      await\s+client\.query\("SELECT\s+set_config\(\x27app\.user_id\x27,\s*\$1,\s*true\);\x22\s*,\s*\[userId\]\);\s*
      (?:\s*\n)?\s*
      await\s+client\.query\("SELECT\s+set_config\(\x27request\.user_role\x27,\s*\$1,\s*true\);\x22\s*,\s*\[role\]\);\s*
      await\s+client\.query\("SELECT\s+set_config\(\x27app\.user_role\x27,\s*\$1,\s*true\);\x22\s*,\s*\[role\]\);\s*
      await\s+client\.query\("SELECT\s+set_config\(\x27rentease\.user_role\x27,\s*\$1,\s*true\);\x22\s*,\s*\[role\]\);\s*
    /\n  await setPgContext(client, { userId, organizationId: orgId, role, eventNote: \"rent_invoices\" });\n/sxg
  ' src/routes/rent_invoices.ts

  echo "✅ Fixed src/routes/rent_invoices.ts (set_config -> setPgContext)"
fi

echo "============================================================"
echo "✅ PASS #2.1 DONE"
echo "Backup: $BACKUP_DIR"
echo ""
echo "Now run:"
echo "  npm run build"
echo "  rg -n \"set_config\\(\" -g'!*.bak*' src/routes src/services | rg -v \"set_pg_context\" || true"
echo "============================================================"
