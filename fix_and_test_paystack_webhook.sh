#!/usr/bin/env bash
set -euo pipefail

echo "== Fix Paystack env loading + test signature =="

# 1) Ensure dotenv exists
if ! npm ls dotenv >/dev/null 2>&1; then
  echo "-> Installing dotenv"
  npm i dotenv
else
  echo "-> dotenv already installed"
fi

# 2) Find your Fastify entry file (first match wins)
ENTRY=""
for f in src/server.ts src/index.ts src/app.ts; do
  if [ -f "$f" ]; then ENTRY="$f"; break; fi
done

if [ -z "$ENTRY" ]; then
  echo "❌ Could not find Fastify entry file (tried src/server.ts src/index.ts src/app.ts)"
  echo "   Tell me which file creates Fastify() and calls app.listen(), and I’ll patch that one."
  exit 1
fi

echo "-> Using entry: $ENTRY"

# 3) Insert import "dotenv/config"; at the top if missing
python3 - <<PY
from pathlib import Path
p = Path("$ENTRY")
txt = p.read_text(encoding="utf-8")
line = 'import "dotenv/config";'
if line not in txt:
    # put it at very top (before other imports)
    txt = line + "\n" + txt
    p.write_text(txt, encoding="utf-8")
    print("✅ Added dotenv/config import")
else:
    print("✅ dotenv/config import already present")
PY

# 4) Ensure there isn't a duplicate webhooks registration (common earlier issue)
# remove duplicate "await app.register(webhooksRoutes);" lines if more than one exists
python3 - <<'PY'
from pathlib import Path
p = Path("src/routes/index.ts")
if not p.exists():
    print("ℹ️ src/routes/index.ts not found; skipping duplicate registration cleanup")
    raise SystemExit(0)

txt = p.read_text(encoding="utf-8").splitlines(True)
out = []
seen = 0
for line in txt:
    if "app.register(webhooksRoutes" in line:
        seen += 1
        if seen > 1:
            continue
    out.append(line)
p.write_text("".join(out), encoding="utf-8")
print("✅ Cleaned duplicate webhooksRoutes registration (if any)")
PY

echo ""
echo "== Now run server with secret in-process =="
echo "In ONE terminal:"
echo '  PAYSTACK_SECRET_KEY="sk_test_your_key_here" npm run dev'
echo ""
echo "In ANOTHER terminal, run this test:"
cat <<'TEST'
API="http://127.0.0.1:4000"
SECRET="sk_test_your_key_here"
BODY='{"event":"ping","data":{}}'

SIG="$(node -e "const crypto=require('crypto'); const secret=process.argv[1]; const body=process.argv[2]; process.stdout.write(crypto.createHmac('sha512', secret).update(Buffer.from(body,'utf8')).digest('hex'))" "$SECRET" "$BODY")"

curl -sS -i -X POST "$API/webhooks/paystack" \
  -H "Content-Type: application/json" \
  -H "x-paystack-signature: $SIG" \
  --data-binary "$BODY" | sed -n '1,35p'
TEST

echo ""
echo "✅ Script done."
