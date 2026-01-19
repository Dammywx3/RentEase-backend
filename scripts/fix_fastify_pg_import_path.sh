#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER="$ROOT/src/server.ts"

if [ ! -f "$SERVER" ]; then
  echo "ERROR: $SERVER not found"
  exit 1
fi

echo "== Fix: server.ts postgres import path =="

# Replace the wrong absolute import "/postgres" with "@fastify/postgres"
# Also handle 'postgres' (bare) if it happened.
perl -i -pe '
  s/import\s+postgres\s+from\s+["\x27]\/postgres["\x27]\s*;/import postgres from "@fastify\/postgres";/g;
  s/import\s+postgres\s+from\s+["\x27]postgres["\x27]\s*;/import postgres from "@fastify\/postgres";/g;
' "$SERVER"

# Ensure the correct import exists (add if missing)
if ! grep -q 'import postgres from "@fastify/postgres";' "$SERVER"; then
  perl -0777 -i -pe '
    s/(import\s+Fastify\s+from\s+["\x27]fastify["\x27];\s*\n)/$1import postgres from "@fastify\/postgres";\n/s
  ' "$SERVER"
fi

echo "✅ Patched import in src/server.ts"
echo "---- Current postgres-related lines:"
grep -n "postgres" "$SERVER" || true
