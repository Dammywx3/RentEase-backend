#!/usr/bin/env bash
set -euo pipefail

FILE="scripts/test_paystack_transfer_webhook.sh"
if [[ ! -f "$FILE" ]]; then
  echo "ERROR: not found: $FILE"
  exit 1
fi

ts=$(date +%s)
bak="${FILE}.bak.${ts}"
cp "$FILE" "$bak"
echo "Backup: $bak"

# Force webhook BODY reference to payout_$PAYOUT_ID
perl -0777 -i -pe '
  s/"reference"\s*:\s*"[^"]*"/"reference":"payout_$PAYOUT_ID"/g;
  # ensure transfer_code exists in payload
  if ($_ !~ /transfer_code/) {
    s/"data"\s*:\s*\{/"data":{"transfer_code":"trf_test_123",/;
  }
' "$FILE"

echo "✅ Patched: $FILE"
rg -n "reference|transfer_code|transfer\.success" "$FILE" || true
