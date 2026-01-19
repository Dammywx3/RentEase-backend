#!/usr/bin/env bash
set -euo pipefail

TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p scripts/.bak

F1="src/services/purchase_refunds.service.ts"
F2="src/services/ledger.service.ts"

backup() {
  local f="$1"
  if [ -f "$f" ]; then
    cp "$f" "scripts/.bak/$(basename "$f").bak.$TS"
    echo "✅ backup -> scripts/.bak/$(basename "$f").bak.$TS"
  else
    echo "❌ missing file: $f"
    exit 1
  fi
}

backup "$F1"
backup "$F2"

echo ""
echo "1) Fix unqualified deleted_at in purchase_refunds.service.ts"
# Replace unqualified "AND deleted_at IS NULL" with "AND pp.deleted_at IS NULL"
# (purchase queries should be aliasing property_purchases as pp)
perl -i -pe '
  s/\bAND\s+deleted_at\s+IS\s+NULL\b/AND pp.deleted_at IS NULL/g;
' "$F1"

echo "2) Remove unqualified deleted_at filters in ledger.service.ts"
# Wallet tables often don't have deleted_at; remove those conditions.
perl -0777 -i -pe '
  s/\s+AND\s+deleted_at\s+IS\s+NULL//g;
  s/\bWHERE\s+deleted_at\s+IS\s+NULL\s+AND\b/WHERE /g;
  s/\bWHERE\s+deleted_at\s+IS\s+NULL\b//g;
' "$F2"

echo "3) Widen refund service type so payment_status can be refunded"
# If the file has a row type with payment_status declared too narrowly (e.g. "paid"),
# widen it to string to avoid TS2367.
perl -0777 -i -pe '
  s/payment_status:\s*"paid"\s*;/payment_status: string;/g;
  s/payment_status:\s*"paid"\s*\|\s*"unpaid"\s*\|\s*"deposit_paid"\s*\|\s*"partially_paid"\s*\|\s*"paid"\s*;/payment_status: string;/g;
' "$F1"

echo ""
echo "🔎 Sanity check (deleted_at occurrences):"
grep -n "deleted_at" "$F1" "$F2" || true

echo ""
echo "🔎 Typecheck..."
npx -y tsc -p tsconfig.json --noEmit

echo ""
echo "✅ DONE"
echo "NEXT:"
echo "  1) restart: npm run dev"
echo "  2) retry refund:"
echo "     curl -sS -X POST \"\$API/v1/purchases/\$PURCHASE_ID/refund\" -H \"content-type: application/json\" -H \"authorization: Bearer \$TOKEN\" -H \"x-organization-id: \$ORG_ID\" -d '{\"refundMethod\":\"card\",\"amount\":2000}' | jq"
