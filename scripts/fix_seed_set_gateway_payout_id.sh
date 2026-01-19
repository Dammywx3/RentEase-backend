#!/usr/bin/env bash
set -euo pipefail

FILE="scripts/seed_payout_account_create_payout_and_test_transfer.sh"
if [[ ! -f "$FILE" ]]; then
  echo "ERROR: not found: $FILE"
  exit 1
fi

ts=$(date +%s)
cp "$FILE" "${FILE}.bak.${ts}"
echo "Backup: ${FILE}.bak.${ts}"

# 1) Ensure TRANSFER_CODE exists (set a stable test code)
# 2) After PAYOUT_ID is created, UPDATE payouts.gateway_payout_id = TRANSFER_CODE
# 3) Ensure webhook payload uses transfer_code=$TRANSFER_CODE
perl -0777 -i -pe '
  # Ensure TRANSFER_CODE is defined near the transfer webhook section
  if ($_ !~ /\bTRANSFER_CODE=/) {
    s/(=== Sending transfer\.success webhook ===\n)/TRANSFER_CODE="trf_test_123"\n\n$1/s;
  }

  # After "✅ PAYOUT_ID=...." insert an update statement to set gateway_payout_id
  s/(✅ PAYOUT_ID=\$PAYOUT_ID\n)/$1\necho\necho "=== Setting payouts.gateway_payout_id ==="\npsql "$DB_URL" -P pager=off -c "update public.payouts set gateway_payout_id='\''${TRANSFER_CODE}'\'' , updated_at=now() where id='\''${PAYOUT_ID}'\''::uuid;"\n/s;

  # Force webhook payload transfer_code to use $TRANSFER_CODE
  s/"transfer_code"\s*:\s*"[^"]*"/"transfer_code":"$TRANSFER_CODE"/g;

' "$FILE"

echo "✅ Patched: $FILE"
echo
echo "---- verify ----"
rg -n "TRANSFER_CODE=|gateway_payout_id|transfer_code" "$FILE" || true
