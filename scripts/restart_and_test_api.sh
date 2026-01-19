#!/usr/bin/env bash
set -euo pipefail

API="${API:-http://127.0.0.1:4000}"

echo "== 0) Check if anything is listening on :4000 =="
if command -v lsof >/dev/null 2>&1; then
  lsof -nP -iTCP:4000 -sTCP:LISTEN || true
elif command -v ss >/dev/null 2>&1; then
  ss -ltnp | grep ':4000' || true
else
  netstat -an 2>/dev/null | grep '\.4000 ' || true
fi
echo

echo "== 1) Start server (background) =="
# pick a package manager
PM=""
if [ -f pnpm-lock.yaml ] && command -v pnpm >/dev/null 2>&1; then PM="pnpm"; fi
if [ -z "${PM}" ] && [ -f yarn.lock ] && command -v yarn >/dev/null 2>&1; then PM="yarn"; fi
if [ -z "${PM}" ] && command -v npm >/dev/null 2>&1; then PM="npm"; fi

if [ -z "${PM}" ]; then
  echo "❌ No package manager found (npm/pnpm/yarn)."
  exit 1
fi

# determine which script exists
SCRIPT=""
HAS() { node -e 'const p=require("./package.json");process.exit(p.scripts && p.scripts[process.argv[1]]?0:1)' "$1"; }

if HAS dev; then SCRIPT="dev"; fi
if [ -z "${SCRIPT}" ] && HAS start; then SCRIPT="start"; fi
if [ -z "${SCRIPT}" ] && HAS serve; then SCRIPT="serve"; fi

if [ -z "${SCRIPT}" ]; then
  echo "❌ Could not find a script (dev/start/serve) in package.json."
  echo "Here are your scripts:"
  node -e 'console.log(require("./package.json").scripts||{})'
  exit 1
fi

LOG=".server.log"
PIDFILE=".server.pid"

# kill any old pidfile process
if [ -f "$PIDFILE" ]; then
  OLD_PID="$(cat "$PIDFILE" 2>/dev/null || true)"
  if [ -n "${OLD_PID}" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    echo "Stopping previous server pid $OLD_PID ..."
    kill "$OLD_PID" 2>/dev/null || true
    sleep 1
  fi
  rm -f "$PIDFILE"
fi

echo "Starting: $PM run $SCRIPT  (logs: $LOG)"
# start in background, capture pid
( "$PM" run "$SCRIPT" ) >"$LOG" 2>&1 &
PID=$!
echo "$PID" >"$PIDFILE"
echo "PID=$PID"
echo

echo "== 2) Wait for health endpoint =="
OK=0
for i in $(seq 1 60); do
  if curl -sS "$API/v1/health" >/dev/null 2>&1 || curl -sS "$API/health" >/dev/null 2>&1; then
    OK=1
    break
  fi
  sleep 0.5
done

if [ "$OK" -ne 1 ]; then
  echo "❌ Server did not come up at $API"
  echo "Last 80 log lines:"
  tail -n 80 "$LOG" || true
  exit 1
fi

echo "✅ Server is up"
echo

echo "== 3) Run auth/org guard tests =="
: "${TOKEN:?TOKEN is not set}"
: "${ORG_ID:?ORG_ID is not set}"

echo "-- missing org => ORG_REQUIRED"
curl -sS "$API/v1/me" -H "Authorization: Bearer $TOKEN" | jq
echo

echo "-- wrong org => FORBIDDEN"
curl -sS "$API/v1/me" -H "Authorization: Bearer $TOKEN" -H "x-organization-id: 00000000-0000-0000-0000-000000000000" | jq
echo

echo "-- correct org => ok"
curl -sS "$API/v1/me" -H "Authorization: Bearer $TOKEN" -H "x-organization-id: $ORG_ID" | jq
echo

echo "== 4) Quick check purchases still works =="
curl -sS "$API/v1/purchases" -H "Authorization: Bearer $TOKEN" -H "x-organization-id: $ORG_ID" | jq '.ok, (.data|length)'
echo

echo "✅ Done."
