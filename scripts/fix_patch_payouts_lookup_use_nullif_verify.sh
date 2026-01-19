#!/usr/bin/env bash
set -euo pipefail

TARGET="scripts/patch_payouts_lookup_use_nullif.sh"

ts="$(date +%s)"
cp "$TARGET" "${TARGET}.bak.${ts}"
echo "Backup: ${TARGET}.bak.${ts}"

# Replace ONLY the verify rg line to use single quotes (prevents $1/$2 expansion)
perl -0777 -i -pe '
  s/rg\s+-n\s+"([^"]*\\\$1[^"]*)"\s+"\$FILE"\s+\|\|\s+true/rg -n \x27$1\x27 "\$FILE" || true/g;
  s/rg\s+-n\s+"([^"]*\\\$2[^"]*)"\s+"\$FILE"\s+\|\|\s+true/rg -n \x27$1\x27 "\$FILE" || true/g;
' "$TARGET"

echo "✅ Patched: $TARGET"
echo "---- verify ----"
rg -n "rg -n" "$TARGET" || true
