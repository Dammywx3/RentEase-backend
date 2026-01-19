#!/usr/bin/env bash
set -euo pipefail

FILE="src/services/payouts.service.ts"
ts="$(date +%s)"
cp "$FILE" "$FILE.bak.$ts"
echo "Backup: $FILE.bak.$ts"

# Fix invalid postgres jsonb literals: {}::jsonb -> '{}'::jsonb, []::jsonb -> '[]'::jsonb
perl -0777 -i -pe "
  s/\\{\\}\\s*::\\s*jsonb/'{}'::jsonb/g;
  s/\\[\\]\\s*::\\s*jsonb/'[]'::jsonb/g;
" "$FILE"

echo "✅ Patched: $FILE"
echo
echo "---- verify ----"
rg -n "\\{\\}::jsonb|\\[\\]::jsonb|'\\{\\}'::jsonb|'\\[\\]'::jsonb" "$FILE" || true
echo
echo "---- typecheck ----"
npx tsc -p tsconfig.json --noEmit
echo "✅ tsc OK"
