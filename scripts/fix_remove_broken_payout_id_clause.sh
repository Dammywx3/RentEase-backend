#!/usr/bin/env bash
set -euo pipefail

FILE="src/services/payouts.service.ts"
ts="$(date +%s)"
cp "$FILE" "${FILE}.bak.${ts}"

# Remove the broken leftover clause:
#   or ( is not null and p.id = ::uuid)
# (and any whitespace around it)
perl -0777 -i -pe '
  s/\n\s*or\s*\(\s*is\s+not\s+null\s+and\s+p\.id\s*=\s*::uuid\s*\)\s*\n/\n/gms;
' "$FILE"

echo "✅ Patched: $FILE (backup: ${FILE}.bak.${ts})"
echo
echo "---- verify ----"
nl -ba "$FILE" | sed -n '345,370p'
echo
echo "---- typecheck ----"
npx tsc -p tsconfig.json --noEmit
echo "✅ tsc OK"
