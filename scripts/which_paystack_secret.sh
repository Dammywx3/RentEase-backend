#!/usr/bin/env bash
set -euo pipefail

# Auto-load .env if present
if [[ -f ".env" ]]; then
  set -a
  source .env
  set +a
fi

ws="${PAYSTACK_WEBHOOK_SECRET:-}"
sk="${PAYSTACK_SECRET_KEY:-}"

echo "PAYSTACK_WEBHOOK_SECRET: len=$(printf '%s' "$ws" | wc -c | tr -d ' ') prefix=$(printf '%s' "$ws" | cut -c1-6) suffix=$(printf '%s' "$ws" | rev | cut -c1-4 | rev)"
echo "PAYSTACK_SECRET_KEY:      len=$(printf '%s' "$sk" | wc -c | tr -d ' ') prefix=$(printf '%s' "$sk" | cut -c1-6) suffix=$(printf '%s' "$sk" | rev | cut -c1-4 | rev)"
echo "SERVER WILL USE: $([[ -n "$ws" ]] && echo PAYSTACK_WEBHOOK_SECRET || echo PAYSTACK_SECRET_KEY)"
