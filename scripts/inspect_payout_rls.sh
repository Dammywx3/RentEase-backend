#!/usr/bin/env bash
set -euo pipefail

: "${DATABASE_URL:?DATABASE_URL is not set}"

OUT_DIR="${PWD}/.db_inspect"
mkdir -p "$OUT_DIR"
OUT_FILE="$OUT_DIR/payout_rls_inspect_$(date +%Y%m%d_%H%M%S).txt"

run() {
  local title="$1"
  local sql="$2"
  {
    echo ""
    echo "============================================================"
    echo "$title"
    echo "============================================================"
    echo "$sql"
    echo ""
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -P pager=off -c "$sql"
  } >> "$OUT_FILE"
}

echo "Writing -> $OUT_FILE"

run "A) Find payout-related tables (public schema)" "
select table_name
from information_schema.tables
where table_schema='public'
  and table_type='BASE TABLE'
  and table_name ilike '%payout%'
order by 1;
"

run "B) Find payout-related enums (if any)" "
select t.typname as enum_name, e.enumlabel as enum_value
from pg_type t
join pg_enum e on e.enumtypid = t.oid
join pg_namespace n on n.oid = t.typnamespace
where n.nspname='public'
  and t.typname ilike '%payout%'
order by 1, e.enumsortorder;
"

run "C) RLS enabled flags for payout tables" "
select
  c.relname as table_name,
  c.relrowsecurity as rls_enabled,
  c.relforcerowsecurity as rls_forced
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname='public'
  and c.relkind='r'
  and c.relname ilike '%payout%'
order by 1;
"

run "D) Policies for payout tables (pg_policies)" "
select
  schemaname,
  tablename,
  policyname,
  roles,
  cmd,
  permissive,
  qual,
  with_check
from pg_policies
where schemaname='public'
  and tablename ilike '%payout%'
order by tablename, policyname;
"

run "E) Columns for payout tables (so we know what to key policies on)" "
select
  table_name,
  column_name,
  data_type,
  is_nullable
from information_schema.columns
where table_schema='public'
  and table_name ilike '%payout%'
order by table_name, ordinal_position;
"

run "F) Show helper functions you mentioned (if they exist)" "
select
  n.nspname as schema,
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname='public'
  and p.proname in ('is_admin','current_user_uuid','current_organization_uuid')
order by 2;
"

run "G) Function definitions (if present) — is_admin()" "
select pg_get_functiondef('public.is_admin()'::regprocedure);
"

run "H) Function definitions — current_user_uuid()" "
select pg_get_functiondef('public.current_user_uuid()'::regprocedure);
"

run "I) Function definitions — current_organization_uuid()" "
select pg_get_functiondef('public.current_organization_uuid()'::regprocedure);
"

echo "DONE ✅  Open the file:"
echo "  $OUT_FILE"