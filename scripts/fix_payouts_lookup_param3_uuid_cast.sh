#!/usr/bin/env bash
set -euo pipefail

FILE="src/services/payouts.service.ts"
ts="$(date +%s)"
cp "$FILE" "$FILE.bak.$ts"
echo "Backup: $FILE.bak.$ts"

# Force param $3 to be explicitly uuid-typed in the lookup query
# Replace any "p.id = $3" or "$3 is not null and p.id = $3" variants with a safe casted form.
perl -0777 -i -pe '
  s/\(\$3\s+is\s+not\s+null\s+and\s+p\.id\s*=\s*\$3(::uuid)?\)/(\$3::uuid is not null and p.id = \$3::uuid)/gmi;
  s/\bp\.id\s*=\s*\$3\b/p.id = \$3::uuid/gmi;
' "$FILE"

echo "✅ Patched: $FILE"
echo
echo "---- verify (show the lookup clause area) ----"
rg -n "p\\.id\\s*=\\s*\\$3|\\$3::uuid" "$FILE" || true
echo
echo "---- typecheck ----"
npx tsc -p tsconfig.json --noEmit
echo "✅ tsc OK"
