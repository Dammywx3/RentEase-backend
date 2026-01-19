#!/usr/bin/env bash
set -euo pipefail

FILE="src/services/payouts.service.ts"
ts="$(date +%s)"
cp "$FILE" "${FILE}.bak.${ts}"

# In finalizePaystackTransferEvent payout lookup query:
# ensure WHERE includes id match from payoutIdFromRef ($3) safely.
perl -0777 -i -pe '
  s/\(\s*p\.gateway_payout_id\s*=\s*nullif\(\$1,\x27\x27\)\s*\)\s*\n\s*or\s*\(\s*p\.gateway_payout_id\s*=\s*nullif\(\$2,\x27\x27\)\s*\)/
(p.gateway_payout_id = nullif(\$1,\x27\x27))
      or (p.gateway_payout_id = nullif(\$2,\x27\x27))
      or (p.id = nullif(\$3::text,\x27\x27\)::uuid)
/gms;
' "$FILE"

echo "✅ Patched: $FILE"
echo
echo "---- verify (show lookup where-clause lines) ----"
rg -n 'gateway_payout_id\s*=\s*nullif\(\$1|gateway_payout_id\s*=\s*nullif\(\$2|p\.id\s*=\s*nullif\(\$3::text' "$FILE" || true
echo
echo "---- typecheck ----"
npx tsc -p tsconfig.json --noEmit
echo "✅ tsc OK"
