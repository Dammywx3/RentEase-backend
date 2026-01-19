#!/usr/bin/env bash
set -euo pipefail

FILE="scripts/e2e_close_purchase.sh"
[ -f "$FILE" ] || { echo "❌ Missing $FILE"; exit 1; }

cp -f "$FILE" "$FILE.bak.$(date +%s)"

# Replace any pipeline call into parse_token_org_user with a here-string call
# so the function runs in the current shell (not a subshell)
sed -i.bak \
  -e 's|^[[:space:]]*printf "%s" "\$LOGIN_BODY" \| parse_token_org_user[[:space:]]*$|parse_token_org_user <<<"$LOGIN_BODY"|' \
  -e 's|^[[:space:]]*printf "%s" "\$LOGIN_JSON" \| parse_token_org_user[[:space:]]*$|parse_token_org_user <<<"$LOGIN_JSON"|' \
  -e 's|^[[:space:]]*printf "%s" "\$LOGIN_RESPONSE" \| parse_token_org_user[[:space:]]*$|parse_token_org_user <<<"$LOGIN_RESPONSE"|' \
  "$FILE" || true

echo "✅ Patched subshell issue in $FILE"
echo "==> Show parser call lines:"
grep -n "parse_token_org_user" "$FILE" | head -n 30
