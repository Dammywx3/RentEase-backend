#!/usr/bin/env bash
set -euo pipefail

DIR="src/routes"

if [ ! -d "$DIR" ]; then
  echo "❌ $DIR not found (run from project root)."
  exit 1
fi

echo "🔧 Normalizing preHandler style to always be an array..."

find "$DIR" -type f -name "*.ts" -print0 | while IFS= read -r -d '' f; do
  # backup once
  [ -f "${f}.bak" ] || cp "$f" "${f}.bak"

  # preHandler: app.authenticate  -> preHandler: [app.authenticate]
  perl -pi -e 's/preHandler:\s*(app\.authenticate)\b/preHandler: [$1]/g' "$f"

  # preHandler: requireAuth -> preHandler: [requireAuth]
  perl -pi -e 's/preHandler:\s*(requireAuth)\b/preHandler: [$1]/g' "$f"

  # preHandler: authGuard -> preHandler: [authGuard]
  perl -pi -e 's/preHandler:\s*(authGuard)\b/preHandler: [$1]/g' "$f"
done

echo "✅ Done."
echo "Backups: src/routes/*.ts.bak"
echo
echo "Restart server, then spot-check a route file diff if you want."
