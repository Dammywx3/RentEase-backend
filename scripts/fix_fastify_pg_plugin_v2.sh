#!/usr/bin/env bash
set -euo pipefail

echo "== Fix v2: register @fastify/postgres so app.pg exists =="

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER="$ROOT/src/server.ts"
PKG="$ROOT/package.json"

if [ ! -f "$SERVER" ]; then
  echo "ERROR: $SERVER not found"
  exit 1
fi

# 1) Install plugin
if ! grep -q '"@fastify/postgres"' "$PKG"; then
  echo "Installing @fastify/postgres..."
  npm i @fastify/postgres
else
  echo "✅ @fastify/postgres already installed"
fi

# 2) Patch server.ts (idempotent)
MARKER="// FASTIFY_PG_REGISTERED"
TMP="$(mktemp)"

awk -v marker="$MARKER" '
BEGIN { hasImport=0; hasMarker=0; n=0 }
{
  n++
  lines[n]=$0
  if ($0 ~ /from "@fastify\/postgres"/) hasImport=1
  if (index($0, marker) > 0) hasMarker=1
}
END {
  for (i=1; i<=n; i++) {
    line=lines[i]
    print line

    # add import right after Fastify import (only if missing)
    if (!hasImport && line ~ /^import Fastify from "fastify";/) {
      print "import postgres from \"@fastify/postgres\";"
    }

    # insert registration block right after registerJwt (only if missing)
    if (!hasMarker && line ~ /await app\.register\(registerJwt\);/) {
      print ""
      print marker
      print "// Provide app.pg for routes that use app.pg.connect()"
      print "const connectionString ="
      print "  process.env.DATABASE_URL ||"
      print "  (env as any).databaseUrl ||"
      print "  (env as any).dbUrl ||"
      print "  (env as any).database_url;"
      print ""
      print "if (!connectionString) {"
      print "  app.log.warn(\"DATABASE_URL is not set; app.pg will not be available.\");"
      print "} else {"
      print "  await app.register(postgres, { connectionString });"
      print "}"
      print ""
    }
  }
}
' "$SERVER" > "$TMP"

mv "$TMP" "$SERVER"

echo "✅ Patched src/server.ts"
echo "➡️ Now restart server: npm run dev"
