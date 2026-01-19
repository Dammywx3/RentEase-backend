#!/usr/bin/env bash
set -euo pipefail

TARGET="scripts/fix_transfer_lookup_sql_rewrite_clean.sh"
ts="$(date +%s)"
cp "$TARGET" "${TARGET}.bak.${ts}"
echo "Backup: ${TARGET}.bak.${ts}"

# Replace the whole "---- verify" rg line with fixed-string greps (no regex, no $ expansion)
perl -0777 -i -pe '
  s/echo "---- verify \(show lookup where-clause lines\) ----"\n.*?(\n\necho "\n---- typecheck ----")/echo "---- verify (show lookup where-clause lines) ----"\nrg -n -F "from public.payouts p" "$FILE" || true\nrg -n -F "gateway_payout_id = nullif(\$1" "$FILE" || true\nrg -n -F "gateway_payout_id = nullif(\$2" "$FILE" || true\nrg -n -F "p.id = nullif(\$3::text" "$FILE" || true$1/sm;
' "$TARGET"

echo "✅ Patched: $TARGET"
echo "---- show verify block ----"
rg -n "verify \\(show lookup|rg -n -F" "$TARGET" || true
