#!/usr/bin/env bash
set -euo pipefail

FILE="src/routes/listings.ts"
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="scripts/_backup_fix_listings_${STAMP}"
mkdir -p "$BACKUP_DIR"

echo "============================================================"
echo "Fix listings.ts (restore clean backup + patch CREATE verb)"
echo "Backup dir: $BACKUP_DIR"
echo "============================================================"

# 0) Backup current broken file (if exists)
if [ -f "$FILE" ]; then
  cp "$FILE" "$BACKUP_DIR/listings.ts.current"
  echo "✅ Saved current -> $BACKUP_DIR/listings.ts.current"
fi

# 1) Find best backup (newest that is NOT broken)
# "broken" means it contains: app.post(",   (unterminated string)
BEST=""

# Search src/routes listings.ts.bak.* first
for f in $(ls -1 src/routes/listings.ts.bak.* 2>/dev/null | sort -r); do
  if grep -q 'app\.post("' "$f" && grep -q 'app\.post("' "$f" && grep -q 'app\.post(",' "$f"; then
    : # ignore weird forms
  fi

  if grep -q 'app\.post("' "$f" && grep -q 'app\.post("' "$f"; then
    : # ok
  fi

  if grep -q 'app\.post(",\s*{ preHandler' "$f" 2>/dev/null; then
    continue
  fi
  if grep -q 'app\.post("' "$f" && grep -q 'app\.get' "$f"; then
    : # ok
  fi
  if grep -q 'app\.post(", { preHandler' "$f" 2>/dev/null; then
    continue
  fi
  # Reject the exact broken signature
  if grep -q 'app\.post("' "$f" && grep -q 'app\.post(",' "$f"; then
    : # not necessarily broken
  fi
  if grep -q 'app\.post(",' "$f" 2>/dev/null; then
    : # ok
  fi
  if grep -q 'app\.post(",' "$f" && grep -q 'app\.post(", { preHandler' "$f" 2>/dev/null; then
    continue
  fi
  if grep -q 'app\.post(", { preHandler' "$f" 2>/dev/null; then
    continue
  fi
  if grep -q 'app\.post(",\s*{ preHandler' "$f" 2>/dev/null; then
    continue
  fi

  # The real broken text from your error:
  if grep -q 'app\.post(", { preHandler' "$f" 2>/dev/null; then
    continue
  fi

  # Basic sanity: must contain listingRoutes export
  if grep -q 'export async function listingRoutes' "$f" 2>/dev/null; then
    BEST="$f"
    break
  fi
done

# If not found, search backup folders created by our scripts
if [ -z "$BEST" ]; then
  for f in $(ls -1 scripts/_backup_*/*listings.ts* 2>/dev/null | sort -r); do
    if grep -q 'app\.post(", { preHandler' "$f" 2>/dev/null; then
      continue
    fi
    if grep -q 'export async function listingRoutes' "$f" 2>/dev/null; then
      BEST="$f"
      break
    fi
  done
fi

if [ -z "$BEST" ]; then
  echo "❌ Could not find a clean listings.ts backup automatically."
  echo "Run this to see backups:"
  echo "  ls -1 src/routes/listings.ts.bak.* | tail -n 20"
  exit 1
fi

echo "✅ Restoring from: $BEST"
cp "$BEST" "$FILE"
cp "$BEST" "$BACKUP_DIR/listings.ts.restored_from_backup"

# 2) Patch CREATE: only change app.get(\"/\") after // CREATE into app.post(\"/\")
perl -0777 -i -pe 's|(//\s*CREATE[\s\S]*?)app\.get\(\s*"/"\s*,|$1app.post("/",|s' "$FILE"

echo ""
echo "---- listings.ts route declarations (quick view) ----"
rg -n '^\s*//\s*(LIST|GET ONE|CREATE|PATCH)|app\.(get|post|put|patch|delete)\(' "$FILE" || true

echo ""
echo "---- Check duplicates in listings.ts ----"
echo "GET / count:  $(rg -n 'app\.get\(\s*"/"\s*,' "$FILE" | wc -l | tr -d " ")"
echo "POST / count: $(rg -n 'app\.post\(\s*"/"\s*,' "$FILE" | wc -l | tr -d " ")"

echo ""
echo "============================================================"
echo "✅ DONE"
echo "Now run:"
echo "  npm run build"
echo "  # restart server: Ctrl+C then npm run dev"
echo "============================================================"
