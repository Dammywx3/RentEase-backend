#!/usr/bin/env bash
set -euo pipefail

echo "== Fix: register @fastify/postgres so app.pg exists =="

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER="$ROOT/src/server.ts"
PKG="$ROOT/package.json"

if [ ! -f "$SERVER" ]; then
  echo "ERROR: $SERVER not found"
  exit 1
fi

# 1) Install plugin if missing
if ! grep -q '"@fastify/postgres"' "$PKG"; then
  echo "Installing @fastify/postgres..."
  npm i @fastify/postgres
else
  echo "✅ @fastify/postgres already in package.json"
fi

# 2) Add import if missing
if ! grep -q 'from "@fastify/postgres"' "$SERVER"; then
  perl -0777 -i -pe '
    s/(import\s+Fastify\s+from\s+"fastify";\s*\n)/$1import postgres from "@fastify\/postgres";\n/
    or die "Could not insert postgres import\n";
  ' "$SERVER"
  echo "✅ Added import postgres from @fastify/postgres"
else
  echo "✅ postgres import already exists"
fi

# 3) Register plugin (idempotent)
if grep -q "FASTIFY_PG_REGISTERED" "$SERVER"; then
  echo "✅ server.ts already patched (marker found)"
  exit 0
fi

perl -0777 -i -pe '
  my $block = qq{

  // FASTIFY_PG_REGISTERED
  // Provide app.pg for routes that use app.pg.connect()
  const connectionString =
    process.env.DATABASE_URL ||
    (env as any).databaseUrl ||
    (env as any).dbUrl ||
    (env as any).database_url;

  if (!connectionString) {
    app.log.warn("DATABASE_URL is not set; app.pg will not be available.");
  } else {
    await app.register(postgres, { connectionString });
  }

};

  # insert right after JWT plugin registration line
  s/(await\s+app\.register\(registerJwt\);\s*\n)/$1$block/s
    or die "Could not find 'await app.register(registerJwt);' to insert postgres registration after.\n";
' "$SERVER"

echo "✅ Patched src/server.ts to register @fastify/postgres (app.pg)."
echo "➡️ Now restart: npm run dev"
