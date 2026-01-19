#!/usr/bin/env bash
set -euo pipefail

FILE="src/routes/index.ts"
if [ ! -f "$FILE" ]; then
  echo "❌ Missing: $FILE"
  exit 1
fi

cp "$FILE" "$FILE.bak.$(date +%s)"

# If already present, exit clean
if grep -qE 'export\s+const\s+registerRoutes\s*=\s*routes\s*;' "$FILE"; then
  echo "✅ registerRoutes already present."
  exit 0
fi

# Insert alias right before export default routes;
perl -0777 -i -pe '
  s/\nexport default routes;\n/\n\/\/ Backwards-compatible alias (src\/server.ts imports { registerRoutes })\nexport const registerRoutes = routes;\n\nexport default routes;\n/s
' "$FILE"

echo "✅ Patched: $FILE (added registerRoutes alias)"
echo "Now verify:"
echo "  grep -n \"registerRoutes\" src/routes/index.ts"
