#!/usr/bin/env bash
set -euo pipefail

FILE="src/services/payouts.service.ts"
ts="$(date +%s)"

cp "$FILE" "$FILE.bak.$ts"
echo "Backup: $FILE.bak.$ts"

# Replace invalid Postgres empty identifier quotes "" with empty string '' inside SQL text
perl -0777 -i -pe '
  s/<> ""/<> '\'''\''/g;
  s/= ""/= '\'''\''/g;
' "$FILE"

echo "✅ Patched: $FILE"
echo
echo "---- verify no invalid \"\" remains ----"
rg -n '<> ""|= ""' "$FILE" || echo "✅ No <> \"\" or = \"\" left"
echo
echo "---- typecheck ----"
npx tsc -p tsconfig.json --noEmit
echo "✅ tsc OK"
