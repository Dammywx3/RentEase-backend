#!/usr/bin/env bash
set -euo pipefail

FILE="src/services/payouts.service.ts"
ts="$(date +%s)"
cp "$FILE" "${FILE}.bak.${ts}"

# Replace any OR-clause that tries to use $3 for payout id lookup
# with a parser-safe version that doesn't use "... not null" on a bad cast.
# We cast ONLY after nullif:
#   or (nullif($3::text,'') is not null and p.id = nullif($3::text,'')::uuid)
perl -0777 -i -pe '
  s{
    \bor\s*\(\s*
      [^)]*\$3[^)]*p\.id\s*=\s*\$3[^)]*
    \)\s*
  }{or (nullif(\$3::text,'') is not null and p.id = nullif(\$3::text,'')::uuid)\n}gmsx;

  # Also fix the common broken variant explicitly, if present
  s{
    \bor\s*\(\s*\$3::uuid\s+is\s+not\s+null\s+and\s+p\.id\s*=\s*\$3::uuid(?:::uuid)?\s*\)\s*
  }{or (nullif(\$3::text,'') is not null and p.id = nullif(\$3::text,'')::uuid)\n}gmsx;
' "$FILE"

echo "✅ Patched: $FILE"
echo
echo "---- verify (show lookup where lines) ----"
rg -n 'nullif\(\$3::text|p\.id\s*=\s*nullif\(\$3::text' "$FILE" || true

echo
echo "---- typecheck ----"
npx tsc -p tsconfig.json --noEmit
echo "✅ tsc OK"
