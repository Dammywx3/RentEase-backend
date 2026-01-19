#!/usr/bin/env bash
set -euo pipefail

TARGET="scripts/fix_payouts_finalize_transfer_lookup.sh"
if [[ ! -f "$TARGET" ]]; then
  echo "ERROR: not found: $TARGET"
  exit 1
fi

ts=$(date +%s)
bak="${TARGET}.bak.${ts}"
cp "$TARGET" "$bak"
echo "Backup: $bak"

# Replace the bad perl invocation line:
#   ' FILE_HINT="$FILE" "$FILE"
# with:
#   ' "$FILE"
# and ensure FILE_HINT is set before perl is called (as env var).
perl -0777 -i -pe '
  s/\x27\s*FILE_HINT="\$FILE"\s*"\$FILE"\s*/\x27 "\$FILE"\n/s;

  # If perl is invoked without FILE_HINT being set as env var on the same line,
  # prepend FILE_HINT="$FILE" before perl (best-effort).
  s/(\n)(perl\s+-0777\s+-i\s+-pe\s+\x27)/$1FILE_HINT="$FILE" $2/s
  unless $_ =~ /FILE_HINT="\$FILE"\s+perl\s+-0777\s+-i\s+-pe/s;
' "$TARGET"

echo "✅ Patched: $TARGET"
echo
echo "---- verify perl line ----"
rg -n "FILE_HINT=|perl -0777 -i -pe" "$TARGET" || true
