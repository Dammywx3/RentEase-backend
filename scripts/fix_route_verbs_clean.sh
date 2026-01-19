#!/usr/bin/env bash
set -euo pipefail

STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="scripts/_backup_fix_route_verbs_clean_${STAMP}"
mkdir -p "$BACKUP_DIR"

backup() {
  local f="$1"
  cp "$f" "$BACKUP_DIR/$(basename "$f")"
}

echo "============================================================"
echo "Fix route verbs (clean + targeted)"
echo "Backup: $BACKUP_DIR"
echo "============================================================"

# -------------------------
# properties.ts: CREATE must be POST "/", LIST is GET "/"
# Find the first app.get("/") after // CREATE and change to app.post("/")
# -------------------------
FILE="src/routes/properties.ts"
if [ -f "$FILE" ]; then
  backup "$FILE"
  perl -0777 -i -pe '
    s/(\/\/\s*CREATE[^\n]*\n\s*)app\.get\(\s*\n(\s*")\s*\/\s*("\s*,)/$1app.post(\n$2\/$3/sm
  ' "$FILE"
  echo "✅ fixed: $FILE (CREATE GET / -> POST /)"
fi

# -------------------------
# listings.ts: CREATE must be POST "/", LIST is GET "/"
# If your listings.ts still has CREATE using get, fix it safely.
# -------------------------
FILE="src/routes/listings.ts"
if [ -f "$FILE" ]; then
  backup "$FILE"
  perl -0777 -i -pe '
    s/(\/\/\s*CREATE[^\n]*\n\s*)app\.get\(\s*"\/"/$1app.post("\/"/sm
  ' "$FILE"
  echo "✅ fixed: $FILE (CREATE GET / -> POST / if present)"
fi

# -------------------------
# viewings.ts:
# - CREATE route is app.get("/") (2nd one) -> app.post("/")
# - PATCH route is app.get("/:id") (2nd one) -> app.patch("/:id")
# -------------------------
FILE="src/routes/viewings.ts"
if [ -f "$FILE" ]; then
  backup "$FILE"

  # 1) Change the CREATE block (the one after "// CREATE") to POST
  perl -0777 -i -pe '
    s/(\/\/\s*CREATE[^\n]*\n\s*)app\.get\(\s*"\/"/$1app.post("\/"/sm
  ' "$FILE"

  # 2) Change the PATCH block (the one after "// PATCH") to PATCH
  perl -0777 -i -pe '
    s/(\/\/\s*PATCH[^\n]*\n\s*)app\.get\(\s*"\/:id"/$1app.patch("\/:id"/sm
  ' "$FILE"

  echo "✅ fixed: $FILE (CREATE -> POST, PATCH -> PATCH)"
fi

# -------------------------
# purchase_escrow.ts: should be POST, not GET
# -------------------------
FILE="src/routes/purchase_escrow.ts"
if [ -f "$FILE" ]; then
  backup "$FILE"
  perl -0777 -i -pe '
    s/(\/\/\s*POST[^\n]*release-escrow[^\n]*\n[\s\S]{0,200}?)app\.get\(\s*"\/:id\/release-escrow"/$1app.post("\/:id\/release-escrow"/sm
  ' "$FILE"
  # Also handle if comment exists but pattern differs
  perl -0777 -i -pe '
    s/app\.get\(\s*"\/:id\/release-escrow"/app.post("\/:id\/release-escrow"/sm
  ' "$FILE"
  echo "✅ fixed: $FILE (GET -> POST for release-escrow)"
fi

# -------------------------
# rent_invoices.ts: pay should be POST, not GET
# -------------------------
FILE="src/routes/rent_invoices.ts"
if [ -f "$FILE" ]; then
  backup "$FILE"
  perl -0777 -i -pe '
    s/(\/\/\s*POST[^\n]*\/rent-invoices\/:id\/pay[^\n]*\n\s*)app\.get\(\s*"\/:id\/pay"/$1app.post("\/:id\/pay"/sm
  ' "$FILE"
  # Fallback
  perl -0777 -i -pe '
    s/app\.get\(\s*"\/:id\/pay"/app.post("\/:id\/pay"/sm
  ' "$FILE"
  echo "✅ fixed: $FILE (GET -> POST for /:id/pay)"
fi

echo ""
echo "============================================================"
echo "✅ DONE"
echo "Now run:"
echo "  npm run build"
echo "  # restart server: Ctrl+C then npm run dev"
echo "  curl -s http://127.0.0.1:4000/debug/routes | rg -n \"properties|listings|viewings|purchases|rent-invoices\" | head -n 200"
echo "  bash scripts/rls_smoke.sh"
echo "============================================================"
