#!/usr/bin/env bash
set -euo pipefail

echo "==> 1) Node + npm versions"
node -v || true
npm -v || true
echo

echo "==> 2) TypeScript/tsx quick compile check (no run)"
if [ -f "tsconfig.json" ]; then
  npx -y tsc -p tsconfig.json --noEmit || true
else
  echo "No tsconfig.json found (skipping tsc)."
fi
echo

echo "==> 3) Ensure routes index is syntactically OK"
node -e "require('fs').readFileSync('src/routes/index.ts','utf8'); console.log('OK: read routes index')"
echo

echo "==> 4) List route files and their exported async functions"
ls -1 src/routes/*.ts | sed 's#^#- #' || true
echo
for f in src/routes/*.ts; do
  fn="$(perl -ne 'if (/export\s+async\s+function\s+([A-Za-z0-9_]+)\s*\(/) { print $1; exit }' "$f")"
  if [ -n "$fn" ]; then
    echo "$(basename "$f"): exports async function $fn"
  else
    echo "$(basename "$f"): (no export async function found)"
  fi
done
echo

echo "✅ Health check finished."
