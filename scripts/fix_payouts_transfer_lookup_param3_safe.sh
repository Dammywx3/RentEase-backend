#!/usr/bin/env bash
set -euo pipefail

FILE="src/services/payouts.service.ts"
ts="$(date +%s)"
cp "$FILE" "${FILE}.bak.${ts}"

perl -0777 -i -pe '
  # Replace any "param3" OR clause variant with a safe one:
  #   or (nullif($3::text,'') is not null and p.id = nullif($3::text,'')::uuid)
  s{
    \bor\s*\(\s*
      [^)]*\$3[^)]*
    \)\s*
  }{
    or (nullif(\$3::text,'') is not null and p.id = nullif(\$3::text,'')::uuid)\n
  }gex;

  # BUT only inside the payout lookup query block (avoid touching other queries)
' "$FILE"

echo "✅ Patched: $FILE"
echo
echo "---- show payout lookup WHERE block ----"
rg -n "from public\\.payouts p|where\\s*\$|gateway_payout_id\\s*=\\s*nullif\\(\\$1|nullif\\(\\$3::text" "$FILE" || true
echo
echo "---- typecheck ----"
npx tsc -p tsconfig.json --noEmit
echo "✅ tsc OK"
