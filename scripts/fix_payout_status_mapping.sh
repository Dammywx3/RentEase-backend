#!/usr/bin/env bash
set -euo pipefail

DB_URL="${DB_URL:-postgres://localhost:5432/rentease}"
FILE="src/services/payouts.service.ts"
ts=$(date +%s)

echo "=== Inspect payout_status enum labels ==="
labels="$(psql "$DB_URL" -qAtX -v ON_ERROR_STOP=1 -c "
select e.enumlabel
from pg_type t
join pg_enum e on e.enumtypid = t.oid
where t.typname = 'payout_status'
order by e.enumsortorder;
")"

if [[ -z "${labels// }" ]]; then
  echo "ERROR: could not read payout_status enum labels."
  exit 1
fi

echo "$labels" | sed 's/^/ - /'
echo

# helper: check if label exists
has_label() {
  local x="$1"
  echo "$labels" | rg -qx "$x"
}

# pick best labels available
SUCCESS="successful"
FAILED="failed"
REVERSED="reversed"

if ! has_label "$SUCCESS"; then
  if has_label "completed"; then SUCCESS="completed"
  elif has_label "paid"; then SUCCESS="paid"
  elif has_label "success"; then SUCCESS="success"
  elif has_label "processed"; then SUCCESS="processed"
  else
    echo "ERROR: could not find a success-like label in payout_status."
    echo "Add one to enum OR tell me the intended 'success' label."
    exit 1
  fi
fi

if ! has_label "$FAILED"; then
  if has_label "error"; then FAILED="error"
  elif has_label "failed"; then FAILED="failed"
  elif has_label "cancelled"; then FAILED="cancelled"
  else
    echo "WARN: could not find a failed-like label; keeping '$FAILED' (may still fail)."
  fi
fi

if ! has_label "$REVERSED"; then
  if has_label "reversal"; then REVERSED="reversal"
  elif has_label "refunded"; then REVERSED="refunded"
  elif has_label "failed"; then REVERSED="failed"
  else
    echo "WARN: could not find reversed-like label; mapping transfer.reversed -> '$FAILED'."
    REVERSED="$FAILED"
  fi
fi

echo "Will map:"
echo " - transfer.success  -> $SUCCESS"
echo " - transfer.failed   -> $FAILED"
echo " - transfer.reversed -> $REVERSED"
echo

cp "$FILE" "${FILE}.bak.${ts}"
echo "Backup: ${FILE}.bak.${ts}"

# Patch the nextStatus mapping block in finalizePaystackTransferEvent
perl -0777 -i -pe "
  s/const nextStatus\\s*=\\s*\\n\\s*evName\\s*===\\s*\\\"transfer\\.success\\\"\\s*\\n\\s*\\?\\s*\\\"[^\\\"]+\\\"\\s*\\n\\s*:\\s*evName\\s*===\\s*\\\"transfer\\.reversed\\\"\\s*\\n\\s*\\?\\s*\\\"[^\\\"]+\\\"\\s*\\n\\s*:\\s*\\\"[^\\\"]+\\\"\\s*;/const nextStatus =\\n    evName === \\\"transfer.success\\\"\\n      ? \\\"$SUCCESS\\\"\\n      : evName === \\\"transfer.reversed\\\"\\n      ? \\\"$REVERSED\\\"\\n      : \\\"$FAILED\\\";/s
" "$FILE"

echo "✅ Patched: $FILE"
echo
echo "---- verify mapping ----"
rg -n "const nextStatus|transfer\\.success|transfer\\.reversed" "$FILE" || true
echo
echo "---- typecheck ----"
npx tsc -p tsconfig.json --noEmit
echo "✅ tsc OK"
