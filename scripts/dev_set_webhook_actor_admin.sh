#!/usr/bin/env bash
set -euo pipefail

DB_URL="${DB_URL:-postgres://localhost:5432/rentease}"
ENV_FILE=".env"

echo "=== Picking a user to act as webhook actor ==="
ACTOR_ID="$(psql "$DB_URL" -qAtX -v ON_ERROR_STOP=1 -c "select id::text from public.users order by created_at asc limit 1;")"
if [[ -z "$ACTOR_ID" ]]; then
  echo "ERROR: no users found in public.users"
  exit 1
fi
echo "ACTOR_ID=$ACTOR_ID"

echo
echo "=== Checking users.role column exists ==="
HAS_ROLE="$(psql "$DB_URL" -qAtX -v ON_ERROR_STOP=1 -c "
select 1
from information_schema.columns
where table_schema='public' and table_name='users' and column_name='role'
limit 1;
")"

if [[ "$HAS_ROLE" != "1" ]]; then
  echo "ERROR: public.users.role column not found. Can't auto-promote to admin."
  echo "Fix: tell me your admin user id (or your schema for users table)."
  exit 1
fi

echo
echo "=== Promoting actor user to admin (DEV ONLY) ==="
psql "$DB_URL" -v ON_ERROR_STOP=1 -c "
update public.users
set role = 'admin'::public.user_role
where id = '$ACTOR_ID'::uuid;
"
echo "✅ Actor promoted to admin."

echo
echo "=== Writing WEBHOOK_ACTOR_USER_ID into .env ==="
if [[ ! -f "$ENV_FILE" ]]; then
  echo "WARN: .env not found, creating new .env"
  touch "$ENV_FILE"
fi

# Replace existing line or append
if rg -n "^WEBHOOK_ACTOR_USER_ID=" "$ENV_FILE" >/dev/null 2>&1; then
  perl -i -pe "s/^WEBHOOK_ACTOR_USER_ID=.*/WEBHOOK_ACTOR_USER_ID=$ACTOR_ID/" "$ENV_FILE"
else
  printf '\nWEBHOOK_ACTOR_USER_ID=%s\n' "$ACTOR_ID" >> "$ENV_FILE"
fi

echo "✅ .env updated:"
rg -n "^WEBHOOK_ACTOR_USER_ID=" "$ENV_FILE" || true

echo
echo "NEXT:"
echo "  1) Restart your dev server so it loads the new .env"
echo "  2) Re-run: bash scripts/seed_payout_account_create_payout_and_test_transfer.sh"
