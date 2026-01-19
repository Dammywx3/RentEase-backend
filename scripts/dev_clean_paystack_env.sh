#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=== Kill anything on :4000 (if running) ==="
if command -v lsof >/dev/null 2>&1; then
  PID="$(lsof -ti tcp:4000 || true)"
  if [[ -n "${PID:-}" ]]; then
    echo "Killing PID(s): $PID"
    kill -9 $PID || true
  else
    echo "No process on :4000"
  fi
else
  echo "lsof not found; skipping port-kill"
fi

echo
echo "=== Remove PAYSTACK_* from current shell ==="
unset PAYSTACK_SECRET_KEY PAYSTACK_WEBHOOK_SECRET PAYSTACK_PUBLIC_KEY || true

echo
echo "=== Load .env into this shell (so it becomes the process env) ==="
if [[ ! -f .env ]]; then
  echo "❌ .env not found in project root"
  exit 1
fi

set -a
source .env
set +a

echo
echo "=== Sanity check (safe print) ==="
sk="${PAYSTACK_SECRET_KEY:-}"
ws="${PAYSTACK_WEBHOOK_SECRET:-}"
echo "PAYSTACK_SECRET_KEY:      len=$(printf '%s' "$sk" | wc -c | tr -d ' ') prefix=$(printf '%s' "$sk" | cut -c1-7) suffix=$(printf '%s' "$sk" | rev | cut -c1-4 | rev)"
echo "PAYSTACK_WEBHOOK_SECRET:  len=$(printf '%s' "$ws" | wc -c | tr -d ' ') prefix=$(printf '%s' "$ws" | cut -c1-7) suffix=$(printf '%s' "$ws" | rev | cut -c1-4 | rev)"
echo "NOTE: server uses webhookSecret = PAYSTACK_WEBHOOK_SECRET ?? PAYSTACK_SECRET_KEY"

echo
echo "=== Start dev server ==="
npm run dev
