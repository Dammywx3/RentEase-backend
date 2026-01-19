#!/usr/bin/env bash
set -euo pipefail

TARGET="scripts/fix_payouts_lookup_uuid_clause.sh"

perl -0777 -i -pe '
  s/rg\s+-n\s+\x27[^\\n]*\x27\s+"\$FILE"\s+\|\|\s+true/rg -n \x27\\$3::uuid\\b|p\\.id\\s*=\\s*\\$3\\b\x27 "\$FILE" || true/g;
  s/rg\s+-n\s+"[^\\n]*"\s+"\$FILE"\s+\|\|\s+true/rg -n \x27\\$3::uuid\\b|p\\.id\\s*=\\s*\\$3\\b\x27 "\$FILE" || true/g;
' "$TARGET"

echo "✅ Patched verify line in: $TARGET"
rg -n "rg -n" "$TARGET" || true
