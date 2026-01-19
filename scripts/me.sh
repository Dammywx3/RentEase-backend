#!/usr/bin/env bash
set -euo pipefail
BASE_URL="${BASE_URL:-http://127.0.0.1:4000}"

if [[ -z "${TOKEN:-}" ]]; then
  echo "TOKEN not set. Run: eval \"\$(./scripts/login.sh)\"" >&2
  exit 1
fi

curl -s "$BASE_URL/v1/me" -H "authorization: Bearer $TOKEN" | jq
