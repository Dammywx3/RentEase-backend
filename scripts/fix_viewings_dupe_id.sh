#!/usr/bin/env bash
set -euo pipefail

FILE="src/routes/viewings.ts"
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="scripts/_backup_fix_viewings_dupe_id_${STAMP}"
mkdir -p "$BACKUP_DIR"

[ -f "$FILE" ] || { echo "❌ Missing $FILE"; exit 1; }
cp "$FILE" "$BACKUP_DIR/$(basename "$FILE")"

echo "============================================================"
echo "Fix viewings.ts duplicate GET /:id (2nd -> PATCH)"
echo "Backup: $BACKUP_DIR/$(basename "$FILE")"
echo "============================================================"

echo ""
echo "---- BEFORE ----"
rg -n 'app\.get\(\s*"\s*/:id' "$FILE" || true

LINE="$(rg -n 'app\.get\(\s*"\s*/:id' "$FILE" | awk -F: 'NR==2{print $1}')"
if [ -z "${LINE:-}" ]; then
  echo "❌ Could not find a 2nd app.get(\"/:id\") in $FILE"
  exit 1
fi

echo "Second GET /:id is on line: $LINE"
perl -pi -e "if (\$. == $LINE) { s/app\.get/app.patch/; }" "$FILE"

echo ""
echo "---- AFTER ----"
rg -n 'app\.get\(\s*"\s*/:id' "$FILE" || true
rg -n 'app\.patch\(\s*"\s*/:id' "$FILE" || true

GETC="$(rg -n 'app\.get\(\s*"\s*/:id' "$FILE" | wc -l | tr -d ' ')"
if [ "$GETC" -gt 1 ]; then
  echo "❌ Still duplicated GET /:id (count=$GETC). Restore backup from:"
  echo "  $BACKUP_DIR/$(basename "$FILE")"
  exit 1
fi

echo ""
echo "✅ Done. Now run:"
echo "  npm run build"
echo "  # restart server: Ctrl+C then npm run dev"
echo "============================================================"
