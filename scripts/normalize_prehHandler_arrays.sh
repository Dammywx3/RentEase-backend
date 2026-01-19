#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$ROOT/src/routes"

if [ ! -d "$DIR" ]; then
  echo "❌ src/routes not found. Run from project root."
  exit 1
fi

echo "🔧 Normalizing preHandler style to arrays in src/routes/*.ts ..."
echo "   Backups will be created as *.bak"

# Replace: preHandler: app.authenticate   -> preHandler: [app.authenticate]
# Replace: preHandler: requireAuth       -> preHandler: [requireAuth]
# Replace: preHandler: requireAdmin      -> preHandler: [...requireAdmin]   (since requireAdmin is already an array)
find "$DIR" -type f -name "*.ts" -print0 | while IFS= read -r -d '' f; do
  perl -pi.bak -e 's/preHandler:\s*app\.authenticate\b/preHandler: [app.authenticate]/g' "$f"
  perl -pi.bak -e 's/preHandler:\s*requireAuth\b/preHandler: [requireAuth]/g' "$f"
  perl -pi.bak -e 's/preHandler:\s*requireAdmin\b/preHandler: [...requireAdmin]/g' "$f"
done

echo "✅ Done."
echo
echo "Next:"
echo "  1) Restart your server"
echo "  2) Sanity check routes:"
echo "     curl -sS \"${API:-http://127.0.0.1:4000}/debug/routes\""
echo
echo "Rollback:"
echo "  find src/routes -type f -name '*.bak' -print0 | while IFS= read -r -d '' b; do mv \"\$b\" \"\${b%.bak}\"; done"
