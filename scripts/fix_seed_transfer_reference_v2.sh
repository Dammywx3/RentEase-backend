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

# Insert/override BODY right before the SIG= line, but only in the transfer section.
# This approach avoids complex regex and avoids bash/JSON quoting issues.
perl -0777 -i -pe '
  # Find the transfer section "=== Sending transfer.success webhook ==="
  # then find the SIG= line inside that section, and inject a new BODY definition above SIG.
  s/(=== Sending transfer\.success webhook ===\n)(.*?\n)(\s*SIG=\$\()/$1$2REF="payout_${PAYOUT_ID}"\nBODY="{\"event\":\"transfer.success\",\"data\":{\"id\":\"trf_test_123\",\"transfer_code\":\"trf_test_123\",\"reference\":\"${REF}\",\"status\":\"success\"}}"\n\n$3/sms;

  # If file already had a BODY= for transfer, this injected BODY overwrites it by being closer to SIG.
' "$FILE"

echo "✅ Patched: $FILE"
echo
echo "---- verify transfer payload lines ----"
rg -n "Sending transfer\.success webhook|REF=\"payout_|BODY=.*transfer\.success|transfer_code|reference" "$FILE" || true
