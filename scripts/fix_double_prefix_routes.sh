#!/usr/bin/env bash
set -euo pipefail

STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="scripts/_backup_double_prefix_${STAMP}"
mkdir -p "$BACKUP_DIR"

echo "============================================================"
echo "RentEase: Fix double-prefix routes (SAFE)"
echo "Backup: $BACKUP_DIR"
echo "============================================================"

backup_file () {
  local f="$1"
  if [[ -f "$f" ]]; then
    cp -a "$f" "$BACKUP_DIR/"
  fi
}

# Remove "/<prefix>" from *route definitions only* (app.get/post/put/patch/delete/etc)
# Example:
#   app.get("/listings", ...)    -> app.get("/", ...)
#   app.get("/listings/:id",...) -> app.get("/:id", ...)
fix_prefix_in_routes () {
  local file="$1"
  local prefix="$2"

  [[ -f "$file" ]] || return 0
  backup_file "$file"

  perl -0777 -i -pe "
    # 1) /prefix/...  -> /...
    s/(app\\.(?:get|post|put|patch|delete|options|head|all)\\(\\s*)([\"'])\\/${prefix}\\/+/\\\$1\\\$2\\//g;

    # 2) /prefix      -> /
    s/(app\\.(?:get|post|put|patch|delete|options|head|all)\\(\\s*)([\"'])\\/${prefix}(?=\\2)/\\\$1\\\$2\\//g;
  " "$file"

  echo "✅ fixed: $file (prefix: /$prefix)"
}

# ------------------------------------------------------------
# A) Fix the known double-prefix route files
# (These are registered with prefix in index.ts, so route files must use "/" and "/:id" etc.)
# ------------------------------------------------------------
fix_prefix_in_routes "src/routes/organizations.ts" "organizations"
fix_prefix_in_routes "src/routes/listings.ts" "listings"
fix_prefix_in_routes "src/routes/applications.ts" "applications"
fix_prefix_in_routes "src/routes/viewings.ts" "viewings"
fix_prefix_in_routes "src/routes/tenancies.ts" "tenancies"
fix_prefix_in_routes "src/routes/rent_invoices.ts" "rent-invoices"
fix_prefix_in_routes "src/routes/payments.ts" "payments"
fix_prefix_in_routes "src/routes/properties.ts" "properties"

# Purchases: index.ts registers purchase_close + purchase_escrow with prefix "/purchases"
fix_prefix_in_routes "src/routes/purchase_close.ts" "purchases"
fix_prefix_in_routes "src/routes/purchase_escrow.ts" "purchases"

# ------------------------------------------------------------
# B) Make debug pgctx route match what smoke expects: GET /debug/pgctx
# Your printRoutes shows "pgctx" currently, so we standardize to /debug/pgctx.
# ------------------------------------------------------------
if [[ -f "src/routes/debug_pgctx.ts" ]]; then
  backup_file "src/routes/debug_pgctx.ts"

  perl -0777 -i -pe '
    s/(app\.get\(\s*)(["'\''])\/pgctx\2/\$1\$2\/debug\/pgctx\$2/g;
  ' src/routes/debug_pgctx.ts

  echo "✅ fixed: src/routes/debug_pgctx.ts (now GET /debug/pgctx)"
fi

echo "============================================================"
echo "✅ DONE"
echo ""
echo "Next steps:"
echo "  npm run build"
echo "  # restart server: npm run dev"
echo "  curl -s http://127.0.0.1:4000/debug/routes | head -n 120"
echo "  bash scripts/rls_smoke.sh"
echo "============================================================"
