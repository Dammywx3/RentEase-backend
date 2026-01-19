#!/usr/bin/env bash
set -euo pipefail

FILE="scripts/seed_payout_account_create_payout_and_test_transfer.sh"
ts=$(date +%s)

cp "$FILE" "${FILE}.bak.${ts}"
echo "Backup: ${FILE}.bak.${ts}"

# Replace the "Create payout_account" block with: SELECT existing OR INSERT new
perl -0777 -i -pe '
  s/=== Create payout_account \(schema-safe\) ===.*?^echo "✅ PAYOUT_ACCT_ID=\$PAYOUT_ACCT_ID"\n/s/=== Create payout_account (reuse if exists) ===\nPAYOUT_ACCT_ID="$(psql "$DB_URL" -qAtX -v ON_ERROR_STOP=1 -c "\nselect id::text\nfrom public.payout_accounts\nwhere user_id='\''$USER_ID'\''::uuid\n  and provider='\''paystack'\''\n  and provider_token='\''TEST_PROVIDER_TOKEN'\''\nlimit 1;\n")"\n\nif [[ -z "${PAYOUT_ACCT_ID}" ]]; then\n  PAYOUT_ACCT_ID="$(psql "$DB_URL" -qAtX -v ON_ERROR_STOP=1 -c "\ninsert into public.payout_accounts (organization_id, user_id, provider, provider_token, currency, label)\nvalues ('\''$ORG_ID'\''::uuid, '\''$USER_ID'\''::uuid, '\''paystack'\'', '\''TEST_PROVIDER_TOKEN'\'', '\''NGN'\'', '\''Test Payout Account'\'')\nreturning id::text;\n")"\n  echo "✅ Created PAYOUT_ACCT_ID=$PAYOUT_ACCT_ID"\nelse\n  echo "✅ Reusing PAYOUT_ACCT_ID=$PAYOUT_ACCT_ID"\nfi\n/sms
' "$FILE"

echo "✅ Patched: $FILE"
echo "---- verify ----"
rg -n "Create payout_account \\(reuse|Reusing PAYOUT_ACCT_ID|TEST_PROVIDER_TOKEN" "$FILE" || true
