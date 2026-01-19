#!/usr/bin/env bash
set -u

FILE="src/routes/applications.ts"
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="scripts/_backup_fix_applications_${STAMP}"
mkdir -p "$BACKUP_DIR"

echo "============================================================"
echo "Fix applications.ts duplicate GET /v1/applications"
echo "Backup dir: $BACKUP_DIR"
echo "============================================================"

if [ ! -f "$FILE" ]; then
  echo "❌ Missing file: $FILE"
  exit 0
fi

cp "$FILE" "$BACKUP_DIR/applications.ts"
echo "✅ Backed up -> $BACKUP_DIR/applications.ts"
echo ""

echo "---- BEFORE (route declarations) ----"
rg -n 'app\.(get|post|put|patch|delete)\(' "$FILE" || true
echo ""

GETCOUNT="$(rg -n 'app\.get\(\s*"\s*/\s*"\s*[,)]' "$FILE" | wc -l | tr -d ' ')"
echo "GET '/' count = $GETCOUNT"

if [ "$GETCOUNT" -lt 2 ]; then
  echo "✅ Not duplicated (GET '/' < 2). Nothing to change."
  exit 0
fi

# Replace ONLY the 2nd app.get("/") with app.post("/")
perl -i -pe '
  BEGIN { $i=0 }
  if (/app\.get\(\s*"\s*\/\s*"\s*[,)]/) {
    $i++;
    if ($i==2) { s/app\.get/app.post/; }
  }
' "$FILE"

echo ""
echo "---- AFTER (route declarations) ----"
rg -n 'app\.(get|post|put|patch|delete)\(' "$FILE" || true
echo ""

GETCOUNT2="$(rg -n 'app\.get\(\s*"\s*/\s*"\s*[,)]' "$FILE" | wc -l | tr -d ' ')"
POSTCOUNT="$(rg -n 'app\.post\(\s*"\s*/\s*"\s*[,)]' "$FILE" | wc -l | tr -d ' ')"
echo "GET '/' count  = $GETCOUNT2"
echo "POST '/' count = $POSTCOUNT"

if [ "$GETCOUNT2" -gt 1 ]; then
  echo "❌ Still duplicated GET '/'. Restore backup:"
  echo "   cp $BACKUP_DIR/applications.ts $FILE"
else
  echo "✅ Fixed applications.ts"
fi

echo "============================================================"
echo "Next:"
echo "  npm run build"
echo "  # restart server: Ctrl+C then npm run dev"
echo "============================================================"
