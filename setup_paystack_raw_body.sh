#!/usr/bin/env bash
set -euo pipefail

npm i @fastify/raw-body

echo ""
echo "Searching for your Fastify entry file..."
ENTRY="$(rg -n --hidden --no-ignore -S "Fastify\\(|fastify\\(" src 2>/dev/null | head -n 1 | cut -d: -f1 || true)"

if [ -z "${ENTRY:-}" ]; then
  echo "❌ I couldn't auto-detect your Fastify entry file."
  echo "Search manually with: rg -n \"Fastify\\(|fastify\\(\" src"
  exit 0
fi

echo "✅ Likely entry file: $ENTRY"
echo ""
echo "Now open it and add:"
echo ""
echo "1) Import:"
echo "   import rawBody from \"@fastify/raw-body\";"
echo ""
echo "2) Register BEFORE routes:"
echo "   await app.register(rawBody, { field: \"rawBody\", global: true, encoding: \"utf8\", runFirst: true });"
echo ""
echo "Done."
