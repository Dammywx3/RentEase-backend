#!/usr/bin/env bash
set -euo pipefail

TARGET="scripts/fix_payouts_lookup_uuid_clause.sh"
[[ -f "$TARGET" ]] || { echo "Missing: $TARGET" >&2; exit 1; }

# 1) Ensure FILE is set (self-contained)
perl -0777 -i -pe '
  if ($_ !~ /^\s*FILE=/m) {
    $_ = "FILE=\"src/services/payouts.service.ts\"\n" . $_;
  } else {
    s/^\s*FILE=.*$/FILE="src\/services\/payouts.service.ts"/m;
  }
' "$TARGET"

# 2) Ensure rg verify line uses single quotes so $3 never expands
perl -0777 -i -pe '
  s/rg\s+-n\s+"p\\\.id\\s*=\s*\\\\\\\$3\|\\\\\\\$3::uuid\\\\b"\s+"\$FILE"/rg -n \x27p\\\.id\\s*=\\s*\\\$3|\\\$3::uuid\\b\x27 "\$FILE"/g;
  s/rg\s+-n\s+"p\\\.id\\s*=\s*\\\\\\\$3\|\\\\\\\$3::uuid\\\\b"\s+"\$\{FILE\}"/rg -n \x27p\\\.id\\s*=\\s*\\\$3|\\\$3::uuid\\b\x27 "\$\{FILE\}"/g;
' "$TARGET"

echo "✅ Patched: $TARGET"
echo "---- verify (show FILE + rg lines) ----"
rg -n '^\s*FILE=|rg -n ' "$TARGET" || true
