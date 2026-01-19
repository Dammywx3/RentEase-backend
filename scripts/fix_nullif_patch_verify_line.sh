#!/usr/bin/env bash
set -euo pipefail

TARGET="scripts/patch_payouts_lookup_use_nullif.sh"

ts="$(date +%s)"
cp "$TARGET" "${TARGET}.bak.${ts}"
echo "Backup: ${TARGET}.bak.${ts}"

# Replace the verify rg line to use single-quotes so $1/$2 don't expand in bash
perl -0777 -i -pe '
  s/rg\s+-n\s+"gateway_payout_id\\s\\*=\\s\\*nullif\\|\\\\\\$1\s*<>\s*'\'''\''\\|\\\\\\$2\s*<>\s*'\'''\''"\s+"\$FILE"\s+\|\|\s+true/rg -n \x27gateway_payout_id\\s*=\\s*nullif|\\$1 <> \x27\x27|\\$2 <> \x27\x27\x27 "\$FILE" || true/g;
  s/rg\s+-n\s+"gateway_payout_id\\s\\*=\\s\\*nullif\\|\\\\\\$1\s*<>\s*'\'''\''\\|\\\\\\$2\s*<>\s*'\'''\''"\s+"\$\{FILE\}"\s+\|\|\s+true/rg -n \x27gateway_payout_id\\s*=\\s*nullif|\\$1 <> \x27\x27|\\$2 <> \x27\x27\x27 "\$\{FILE\}" || true/g;
' "$TARGET"

echo "✅ Patched: $TARGET"
echo "---- show verify line ----"
rg -n "rg -n" "$TARGET" || true
