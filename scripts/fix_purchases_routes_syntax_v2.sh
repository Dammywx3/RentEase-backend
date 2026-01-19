#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

FILE="src/routes/purchases.routes.ts"

if [ ! -f "$FILE" ]; then
  echo "❌ File not found: $FILE"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP="$FILE.bak.recover.$TS"
cp "$FILE" "$BACKUP"
echo "==> Backup: $BACKUP"

# ------------------------------------------------------------
# A) If the file accidentally contains a duplicated full copy
#    (2nd occurrence of the header), keep only the first copy.
# ------------------------------------------------------------
TMP1="$(mktemp)"
awk '
  BEGIN{c=0}
  /^\/\/ src\/routes\/purchases\.routes\.ts/ { c++; if (c==2) exit }
  { print }
' "$FILE" > "$TMP1"
mv "$TMP1" "$FILE"
echo "==> Dedupe header pass done."

# ------------------------------------------------------------
# B) Remove the corrupted "app.event_note" injection block/line
#    (this is what caused "Unterminated string literal").
#    We remove:
#      - the whole optional block if it exists, AND/OR
#      - any stray broken line containing app.event_note
# ------------------------------------------------------------
perl -0777 -i -pe '
  # remove full optional block (safe if not present)
  s@\n\s*//\s*Optional:\s*pass a note to the DB trigger via session setting.*?\n\s*if\s*\(typeof\s+note\s*==\s*"string".*?\n\s*}\s*else\s*\{\s*\n\s*await\s+client\.query\("select\s+set_config\(\x27app\.event_note\x27,\s*\x27\x27,\s*false\)"\);\s*\n\s*}\s*\n@@ms;

  # remove any single corrupted line containing app.event_note (unterminated string scenario)
  s@^[^\n]*app\.event_note[^\n]*\n@@mg;
' "$FILE"

echo "==> Removed any app.event_note corruption (if present)."

# ------------------------------------------------------------
# C) Quick sanity output
# ------------------------------------------------------------
echo "==> Sanity checks:"
echo -n " - header_count="
grep -n "^// src/routes/purchases.routes.ts" -n "$FILE" | wc -l | tr -d " "
echo -n " - export_default_count="
grep -n "export default async function purchasesRoutes" -n "$FILE" | wc -l | tr -d " "
echo " - status_route_lines:"
grep -n "/purchases/:purchaseId/status" -n "$FILE" | head -n 5 || true

echo "✅ Fixed: $FILE"
echo "==> Next: run your build to confirm:"
echo "   npm run build"
