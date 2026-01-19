#!/usr/bin/env bash
set -euo pipefail

TARGET="scripts/fix_transfer_lookup_sql_rewrite_clean.sh"
ts="$(date +%s)"
cp "$TARGET" "${TARGET}.bak.${ts}"
echo "Backup: ${TARGET}.bak.${ts}"

perl -0777 -i -pe '
  # Replace everything from the verify echo line up to the next "---- typecheck ----" header
  s/echo "---- verify \(show lookup where-clause lines\) ----"\n[\s\S]*?echo "\n---- typecheck ----"/echo "---- verify (show lookup where-clause lines) ----"\nrg -n -F "from public.payouts p" "\$FILE" || true\nrg -n -F "gateway_payout_id = nullif(\$1" "\$FILE" || true\nrg -n -F "gateway_payout_id = nullif(\$2" "\$FILE" || true\nrg -n -F "p.id = nullif(\$3::text" "\$FILE" || true\necho "\n---- typecheck ----"/sm;
' "$TARGET"

echo "✅ Patched: $TARGET"
echo "---- show verify block ----"
rg -n 'verify \(show lookup|rg -n -F|typecheck' "$TARGET" || true
