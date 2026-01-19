#!/usr/bin/env bash
set -euo pipefail

DB="${DB:-rentease}"
PURCHASE_ID="${1:-}"
ORG_ID="${2:-}"
ACTOR_ID="${3:-}"

if [ -z "$PURCHASE_ID" ]; then
  echo "Usage:"
  echo "  DB=rentease ./scripts/db_debug_close_purchase_error.sh <PURCHASE_ID> [ORG_ID] [ACTOR_ID]"
  exit 1
fi

echo "==> Showing function defs (purchase_close_complete + safe_audit_log)..."
psql -X -P pager=off -d "$DB" -c "
select p.oid::regprocedure as fn, pg_get_functiondef(p.oid) as def
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in ('purchase_close_complete','safe_audit_log')
order by 1;
" || true

echo
echo "==> Calling purchase_close_complete directly to get CONTEXT (line number)..."
# Build a call that matches your signature with defaults if org/actor not supplied
if [ -n "${ORG_ID:-}" ] && [ -n "${ACTOR_ID:-}" ]; then
  psql -X -P pager=off -d "$DB" -v ON_ERROR_STOP=1 -c "
  select public.purchase_close_complete(
    '$PURCHASE_ID'::uuid,
    '$ORG_ID'::uuid,
    '$ACTOR_ID'::uuid,
    'debug-call'
  );
  "
else
  psql -X -P pager=off -d "$DB" -v ON_ERROR_STOP=1 -c "
  select public.purchase_close_complete(
    '$PURCHASE_ID'::uuid
  );
  "
fi

echo
echo "✅ Done."
