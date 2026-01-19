#!/usr/bin/env bash
set -euo pipefail

FILE="src/services/payouts.service.ts"
ts="$(date +%s)"
cp "$FILE" "${FILE}.bak.${ts}"

# Replace ONLY the problematic "$3::uuid is not null ..." OR clause with a safe nullif() version.
perl -0777 -i -pe '
  s/or\s*\(\s*\$3::uuid\s+is\s+not\s+null\s+and\s+p\.id\s*=\s*\$3::uuid(?:::uuid)?\s*\)/
or (nullif(\$3::text,\x27\x27) is not null and p.id = nullif(\$3::text,\x27\x27)::uuid)
/gms;
' "$FILE"

echo "✅ Patched: $FILE"
echo
echo "---- verify (show param3 clause) ----"
rg -n 'nullif\(\$3::text|p\.id\s*=\s*nullif\(\$3::text|\$3::uuid\s+is\s+not\s+null' "$FILE" || true

echo
echo "---- typecheck ----"
npx tsc -p tsconfig.json --noEmit
echo "✅ tsc OK"
