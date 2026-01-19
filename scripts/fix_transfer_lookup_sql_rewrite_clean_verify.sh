#!/usr/bin/env bash
set -euo pipefail

TARGET="scripts/fix_transfer_lookup_sql_rewrite_clean.sh"
ts="$(date +%s)"
cp "$TARGET" "${TARGET}.bak.${ts}"

# If an rg verify line contains \$1/\$2/\$3, switch pattern quotes from "..." to '...'
perl -0777 -i -pe '
  s/rg\s+-n\s+"([^"\n]*\\\$[123][^"\n]*)"\s+"(\$FILE|\$\{FILE\})"/rg -n \x27$1\x27 "$2"/g;
' "$TARGET"

echo "✅ Patched verify line(s) in: $TARGET"
rg -n "rg -n" "$TARGET" || true
