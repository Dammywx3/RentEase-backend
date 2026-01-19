#!/usr/bin/env bash
set -euo pipefail

FILE="src/services/purchase_refunds.service.ts"
[ -f "$FILE" ] || { echo "❌ missing $FILE"; exit 1; }

echo "==> showing any suspicious '::' casts in $FILE"
grep -nE '::(uuid|text|purchase_payment_status)' "$FILE" || true

echo ""
echo "==> showing suspicious patterns where something may be missing before ::"
grep -nE '(,\s*::uuid|\(\s*::uuid|\$\{[^}]*\}::uuid)' "$FILE" || true

echo ""
echo "==> printing the upsertRefundMilestones UPDATE block area"
# print around the UPDATE statement
awk '
  /async function upsertRefundMilestones/ {p=1}
  p==1 {print NR ":" $0}
  p==1 && /END_UPSERT_REFUND_MILESTONES_MARKER/ {p=0}
' "$FILE" 2>/dev/null || true

echo ""
echo "Tip: if you see something like ::uuid with nothing before it, that's your 42601."
