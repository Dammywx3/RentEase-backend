#!/usr/bin/env bash
set -euo pipefail

FILE="scripts/seed_payout_account_create_payout_and_test_transfer.sh"
ts=$(date +%s)
cp "$FILE" "${FILE}.bak.${ts}"
echo "Backup: ${FILE}.bak.${ts}"

# Add -q -t -A -X to the 2 capture queries (payout_account + payout)
perl -0777 -i -pe '
  s/PAYOUT_ACCT_ID="\$\((psql\s+"\$DB_URL"\s+-P\s+pager=off\s+-Atc)/PAYOUT_ACCT_ID="\$\(($1 -q -t -A -X)/s;
  s/PAYOUT_ID="\$\((psql\s+"\$DB_URL"\s+-P\s+pager=off\s+-Atc)/PAYOUT_ID="\$\(($1 -q -t -A -X)/s;
' "$FILE"

echo "✅ Patched captures in: $FILE"
echo "---- verify ----"
rg -n 'PAYOUT_ACCT_ID="\$\(\s*psql|PAYOUT_ID="\$\(\s*psql' "$FILE" || true
