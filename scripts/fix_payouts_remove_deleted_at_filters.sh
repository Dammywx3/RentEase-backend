#!/usr/bin/env bash
set -euo pipefail

echo "=== Fix: remove payouts.deleted_at filters (payouts table has no deleted_at) ==="
ROOT="$(pwd)"
echo "PWD: $ROOT"

FILES=(
  "src/routes/webhooks.ts"
  "src/services/payouts.service.ts"
)

ts="$(date +%s)"

for f in "${FILES[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "❌ Missing file: $f"
    exit 1
  fi

  cp "$f" "$f.bak.$ts"
  echo "Backup: $f.bak.$ts"

  # Remove deleted_at checks that reference payouts alias (p.deleted_at) or plain deleted_at in payouts queries
  perl -0777 -i -pe '
    # remove: AND p.deleted_at IS NULL (any spacing/case)
    s/\n\s*and\s+p\.deleted_at\s+is\s+null\s*//ig;

    # remove: AND deleted_at IS NULL (only if it's in a payouts context; best-effort)
    s/\n\s*and\s+deleted_at\s+is\s+null\s*//ig;

    # also handle inline "... AND p.deleted_at is null" on same line
    s/\s+and\s+p\.deleted_at\s+is\s+null\b//ig;

    # also handle inline "... AND deleted_at is null"
    s/\s+and\s+deleted_at\s+is\s+null\b//ig;
  ' "$f"

  echo "✅ Patched: $f"
done

echo
echo "---- verify: any remaining payouts deleted_at references ----"
rg -n "p\.deleted_at|from public\.payouts[\\s\\S]*deleted_at|public\\.payouts[\\s\\S]*deleted_at" src/routes/webhooks.ts src/services/payouts.service.ts || echo "✅ No deleted_at references remain in those files."

echo
echo "---- typecheck ----"
npx tsc -p tsconfig.json --noEmit
echo "✅ tsc OK"

echo
echo "NEXT:"
echo "  1) Restart dev server (tsx watch reload is fine, but safest is restart)"
echo "  2) Run: bash scripts/seed_payout_account_create_payout_and_test_transfer.sh"
