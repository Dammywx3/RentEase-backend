#!/usr/bin/env bash
set -euo pipefail

: "${BASE:?Missing BASE in env (.env)}"
: "${PAYSTACK_SECRET_KEY:?Missing PAYSTACK_SECRET_KEY in env (.env)}"
: "${TX_REF:?Missing TX_REF in env (set to transaction_reference)}"

URL="$BASE/webhooks/paystack"

# Paystack signs the RAW request body with HMAC-SHA512 using secret key
BODY=$(cat <<JSON
{"event":"charge.success","data":{"reference":"$TX_REF","amount":200000,"currency":"NGN","id":123456}}
JSON
)

SIG="$(printf '%s' "$BODY" \
  | openssl dgst -sha512 -hmac "$PAYSTACK_SECRET_KEY" \
  | awk '{print $2}')"

echo "-> POST $URL"
echo "-> TX_REF=$TX_REF"
echo "-> SIG_PREFIX=${SIG:0:16}"

curl -i -sS \
  -X POST "$URL" \
  -H "Content-Type: application/json" \
  -H "x-paystack-signature: $SIG" \
  --data-binary "$BODY"

echo
echo "DONE"