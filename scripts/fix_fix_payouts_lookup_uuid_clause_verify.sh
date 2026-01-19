#!/usr/bin/env bash
set -euo pipefail

TARGET="scripts/fix_payouts_lookup_uuid_clause.sh"

if [[ ! -f "$TARGET" ]]; then
  echo "ERROR: not found: $TARGET" >&2
  exit 1
fi

ts="$(date +%s)"
cp "$TARGET" "${TARGET}.bak.${ts}"
echo "Backup: ${TARGET}.bak.${ts}"

# Replace the rg line to avoid $3 expansion by bash (use single quotes)
perl -0777 -i -pe '
  s/rg\s+-n\s+"p\\\.id\\s\\\*=\\s\\\*\\\\\\\$3\\|\\\\\\\$3::uuid\\\\b"\s+"\\\$FILE"/rg -n \x27p\\\.id\\s\\\*=\\s\\\*\\\$3|\\\$3::uuid\\b\x27 "\$FILE"/g;
' "$TARGET"

echo "✅ Patched: $TARGET"
echo
echo "---- show verify line ----"
rg -n "rg -n 'p\\\.id" "$TARGET" || true
