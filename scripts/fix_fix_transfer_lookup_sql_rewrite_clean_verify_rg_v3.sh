#!/usr/bin/env bash
set -euo pipefail

TARGET="scripts/fix_transfer_lookup_sql_rewrite_clean.sh"
ts="$(date +%s)"
cp "$TARGET" "${TARGET}.bak.${ts}"
echo "Backup: ${TARGET}.bak.${ts}"

tmp="$(mktemp)"

awk '
  BEGIN { in_verify=0; inserted=0 }

  # Enter verify block after the header line
  $0 ~ /^echo "---- verify \(show lookup where-clause lines\) ----"$/ {
    print $0
    in_verify=1
    if (!inserted) {
      print "rg -n -F \"from public.payouts p\" \"$FILE\" || true"
      print "rg -n -F \"gateway_payout_id = nullif(\\$1\" \"$FILE\" || true"
      print "rg -n -F \"gateway_payout_id = nullif(\\$2\" \"$FILE\" || true"
      print "rg -n -F \"p.id = nullif(\\$3::text\" \"$FILE\" || true"
      inserted=1
    }
    next
  }

  # While inside verify block, drop any existing rg lines (we’re standardizing them)
  in_verify && $0 ~ /^rg[[:space:]]+-n/ { next }

  # Exit verify block when typecheck header shows up
  $0 ~ /^echo "---- typecheck ----"$/ {
    in_verify=0
    print $0
    next
  }

  { print $0 }
' "$TARGET" > "$tmp"

mv "$tmp" "$TARGET"
chmod +x "$TARGET"

echo "✅ Patched: $TARGET"
echo "---- show verify block ----"
nl -ba "$TARGET" | sed -n '25,55p'
