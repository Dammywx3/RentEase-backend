#!/usr/bin/env bash
set -euo pipefail

FILE="scripts/seed_payout_account_create_payout_and_test_transfer.sh"
if [[ ! -f "$FILE" ]]; then
  echo "ERROR: not found: $FILE"
  exit 1
fi

ts=$(date +%s)
bak="${FILE}.bak.${ts}"
cp "$FILE" "$bak"
echo "Backup: $bak"

# Replace BODY to use reference payout_$PAYOUT_ID and include transfer_code
perl -0777 -i -pe '
  # Replace any BODY=... block that contains event transfer.success
  s/BODY='\''\{.*?"event"\s*:\s*"transfer\.success".*?\}'\''/BODY='\''{\n  "event":"transfer.success",\n  "data":{\n    "id":"trf_test_123",\n    "transfer_code":"trf_test_123",\n    "reference":"payout_'$PAYOUT_ID'",\n    "status":"success"\n  }\n}'\''/sg;

  # If no BODY block exists, insert one before SIG= line
  if ($_ !~ /BODY='\''\{[^']*transfer\.success/s) {
    s/(=== Sending transfer\.success webhook ===\n)/$1\nBODY='\''{\n  "event":"transfer.success",\n  "data":{\n    "id":"trf_test_123",\n    "transfer_code":"trf_test_123",\n    "reference":"payout_\$PAYOUT_ID",\n    "status":"success"\n  }\n}'\''\n\n/s;
  }

' "$FILE"

echo "✅ Patched: $FILE"
echo
echo "---- verify (show transfer payload area) ----"
rg -n "Sending transfer\.success webhook|BODY=|transfer_code|reference" "$FILE" || true
