#!/usr/bin/env bash
set -euo pipefail

FILE="src/routes/webhooks.ts"
ts="$(date +%s)"

cp "$FILE" "$FILE.bak.$ts"
echo "Backup: $FILE.bak.$ts"

# Remove "where p.deleted_at is null" (payouts table doesn't have deleted_at)
perl -0777 -i -pe '
  s/\bwhere\s+p\.deleted_at\s+is\s+null\b/where 1=1/ig;
  s/\band\s+p\.deleted_at\s+is\s+null\b//ig;
' "$FILE"

echo "✅ Patched: $FILE"
echo
echo "---- verify ----"
rg -n "p\.deleted_at|deleted_at" "$FILE" || echo "✅ No deleted_at refs in webhooks.ts"
echo
echo "---- typecheck ----"
npx tsc -p tsconfig.json --noEmit
echo "✅ tsc OK"
