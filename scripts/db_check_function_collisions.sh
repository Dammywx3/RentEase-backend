#!/usr/bin/env bash
set -euo pipefail

DB="${DB:-rentease}"
FN="${1:-get_or_create_user_wallet_account}"

echo "==> Checking function collisions/overloads for: ${FN}(...)"
echo "==> DB: $DB"
echo

psql -X -P pager=off -d "$DB" -v ON_ERROR_STOP=1 -v FN="$FN" <<'SQL'
\set ON_ERROR_STOP on

-- 1) List ALL functions with this name in ANY schema
WITH f AS (
  SELECT
    n.nspname AS schema,
    p.proname AS name,
    p.oid,
    pg_get_function_identity_arguments(p.oid) AS identity_args,
    pg_get_function_result(p.oid) AS result_type,
    l.lanname AS lang,
    p.prosecdef,
    pg_get_userbyid(p.proowner) AS owner,
    (p.proargdefaults IS NOT NULL) AS has_defaults
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  JOIN pg_language l ON l.oid = p.prolang
  WHERE p.proname = :'FN'
)
SELECT
  schema,
  name,
  identity_args,
  result_type,
  lang,
  CASE WHEN has_defaults THEN 'YES' ELSE 'NO' END AS has_defaults,
  CASE WHEN prosecdef THEN 'SECURITY DEFINER' ELSE 'SECURITY INVOKER' END AS security,
  owner,
  oid::regprocedure AS regprocedure
FROM f
ORDER BY schema, identity_args;

\echo
\echo '---'
\echo '2) Specifically show public.get_or_create_user_wallet_account signatures + defaults'
SELECT
  n.nspname AS schema,
  p.proname AS name,
  pg_get_function_identity_arguments(p.oid) AS identity_args,
  CASE WHEN (p.proargdefaults IS NOT NULL) THEN 'YES' ELSE 'NO' END AS has_defaults,
  p.oid::regprocedure AS regprocedure
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND p.proname = :'FN'
ORDER BY identity_args;

\echo
\echo '---'
\echo '3) If "has_defaults=YES" on the 3-arg fn, and you also have a 1-arg wrapper => that causes "not unique".'
SQL

echo
echo "✅ Done."
