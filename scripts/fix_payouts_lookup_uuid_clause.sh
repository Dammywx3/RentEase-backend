#!/usr/bin/env bash
set -euo pipefail
FILE="src/services/payouts.service.ts"

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: file not found: $FILE" >&2
  exit 1
fi

ts="$(date +%s)"
cp "$FILE" "${FILE}.bak.${ts}"
echo "Backup: ${FILE}.bak.${ts}"

# Replace the broken clause:
#   or ($3::uuid is not null and p.id = $3::uuid::uuid)
# with:
#   or ($3 is not null and p.id = $3::uuid)
perl -0777 -i -pe '
  s/\bor\s*\(\s*\$3::uuid\s+is\s+not\s+null\s+and\s+p\.id\s*=\s*\$3::uuid::uuid\s*\)/
    or ($3 is not null and p.id = $3::uuid)
  /gix;
' "$FILE"

echo "✅ Patched: $FILE"
echo
echo "---- verify ----"
rg -n 'p\\.id\\s*=\\s*\\$3|\\$3::uuid\\b' "$FILE" || true
echo
echo "---- typecheck ----"
npx tsc -p tsconfig.json --noEmit
echo "✅ tsc OK"
