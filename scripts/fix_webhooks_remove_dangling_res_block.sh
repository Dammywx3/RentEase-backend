#!/usr/bin/env bash
set -euo pipefail

FILE="src/routes/webhooks.ts"
ts="$(date +%s)"

cp "$FILE" "$FILE.bak.$ts"
echo "Backup: $FILE.bak.$ts"

# Remove the old/dangling block that references `res` after our new do{...}while(0) block.
# This targets the specific warn-only block:
#   if (!res.ok) {
#     app.log.warn({ error: res.error, reference: ... }, "paystack transfer finalize failed");
#   }
perl -0777 -i -pe '
  s/\n\s*if\s*\(\s*!\s*res\.ok\s*\)\s*\{\s*\n\s*app\.log\.warn\(\s*\{\s*error:\s*res\.error\s*,\s*reference:\s*ctx\.reference\s*,\s*orgId:\s*ctx\.organizationId\s*\}\s*,\s*"paystack transfer finalize failed"\s*\)\s*;\s*\n\s*\}\s*\n/\n/sm;
' "$FILE"

echo "✅ Patched: $FILE"
echo
echo "---- verify no dangling res ----"
rg -n "Cannot find name 'res'|if \\(!res\\.ok\\)" "$FILE" || true
echo
echo "---- typecheck ----"
npx tsc -p tsconfig.json --noEmit
echo "✅ tsc OK"
