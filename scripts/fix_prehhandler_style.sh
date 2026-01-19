#!/usr/bin/env bash
set -euo pipefail

ROUTES_DIR="src/routes"

if [ ! -d "$ROUTES_DIR" ]; then
  echo "❌ Can't find $ROUTES_DIR (run this from your project root)."
  exit 1
fi

echo "🔧 Standardizing preHandler style to: preHandler: [app.authenticate]"

# Find TS route files
find "$ROUTES_DIR" -type f -name "*.ts" -print0 | while IFS= read -r -d '' f; do
  # backup each file once
  cp "$f" "$f.bak_preh" 2>/dev/null || true

  # Replace "preHandler: app.authenticate" with "preHandler: [app.authenticate]"
  perl -pi -e 's/preHandler:\s*app\.authenticate\b/preHandler: [app.authenticate]/g' "$f"

  # Replace "{ preHandler: [app.authenticate] }" already ok (no change)
done

echo "✅ Done. Backups created as *.bak_preh"
echo "Restart server after this."
echo "Rollback:"
echo "  find $ROUTES_DIR -type f -name '*.bak_preh' -print0 | while IFS= read -r -d '' b; do mv \"\$b\" \"\${b%.bak_preh}\"; done"
