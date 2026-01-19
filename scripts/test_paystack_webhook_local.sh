#!/usr/bin/env bash
set -euo pipefail

URL="${1:-http://127.0.0.1:4000/webhooks/paystack}"

BODY="${BODY:-{"event":"charge.success","data":{"id":"ps_test_123","reference":"test-purchase-e2e-d3761464-f54d-43ba-92a1-b8e4681e6e88","amount":200000,"currency":"NGN","status":"success"}}}"

# Match payment.config.ts behavior:
# webhookSecret = PAYSTACK_WEBHOOK_SECRET ?? PAYSTACK_SECRET_KEY
SECRET="${PAYSTACK_WEBHOOK_SECRET:-${PAYSTACK_SECRET_KEY:-}}"
if [[ -z "${SECRET}" ]]; then
  echo "❌ Missing PAYSTACK_SECRET_KEY (or PAYSTACK_WEBHOOK_SECRET)"
  exit 1
fi

# Remove hidden CR/LF so it matches your server's .trim()
SECRET="$(printf '%s' "$SECRET" | tr -d '\r\n')"

SIG="$(SECRET="$SECRET" BODY="$BODY" node --input-type=module -e '
import crypto from "node:crypto";
const secret = process.env.SECRET || "";
const body = process.env.BODY || "";
process.stdout.write(
  crypto.createHmac("sha512", secret).update(Buffer.from(body, "utf8")).digest("hex")
);
')"

echo "Using secret source: $([[ -n "${PAYSTACK_WEBHOOK_SECRET:-}" ]] && echo PAYSTACK_WEBHOOK_SECRET || echo PAYSTACK_SECRET_KEY)"
echo "SIG len: $(printf '%s' "$SIG" | wc -c | tr -d " ")"
echo

curl -i -X POST "$URL" \
  -H "Content-Type: application/json" \
  -H "x-paystack-signature: $SIG" \
  --data "$BODY"
