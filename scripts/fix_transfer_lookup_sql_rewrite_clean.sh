#!/usr/bin/env bash
set -euo pipefail

FILE="src/services/payouts.service.ts"
ts="$(date +%s)"
cp "$FILE" "${FILE}.bak.${ts}"

perl -0777 -i -pe '
  my $new_sql = q{
    select
      p.id::text as id,
      p.organization_id::text as organization_id,
      p.status::text as status
    from public.payouts p
    where
      p.gateway_payout_id = nullif($1, '''')
      or p.gateway_payout_id = nullif($2, '''')
      or p.id = nullif($3::text, '''')::uuid
    limit 1
    for update;
  };

  s{
    (const\s+found\s*=\s*await\s+client\.query<[\s\S]*?>\(\s*`)
    [\s\S]*?
    (`\s*,\s*\[\s*transferCode\s*,\s*ref\s*,\s*payoutIdFromRef\s*\]\s*\)\s*;)
  }{$1\n$new_sql\n$2}gms;
' "$FILE"

echo "✅ Patched: $FILE"
echo
echo "---- verify (show lookup where-clause lines) ----"
rg -n -F "from public.payouts p" "$FILE" || true
rg -n -F "gateway_payout_id = nullif(\$1" "$FILE" || true
rg -n -F "gateway_payout_id = nullif(\$2" "$FILE" || true
rg -n -F "p.id = nullif(\$3::text" "$FILE" || true
echo
echo "---- typecheck ----"
npx tsc -p tsconfig.json --noEmit
echo "✅ tsc OK"
