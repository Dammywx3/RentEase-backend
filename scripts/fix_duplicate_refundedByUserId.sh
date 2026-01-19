#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROUTES="$ROOT/src/routes/purchases.routes.ts"

[ -f "$ROUTES" ] || { echo "❌ Not found: $ROUTES"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$ROOT/scripts/.bak"
cp "$ROUTES" "$ROOT/scripts/.bak/purchases.routes.ts.bak.$TS"
echo "✅ backup -> scripts/.bak/purchases.routes.ts.bak.$TS"

ROUTES_PATH="$ROUTES" python3 - <<'PY'
import os
from pathlib import Path

routes = Path(os.environ["ROUTES_PATH"])
text = routes.read_text(encoding="utf-8")

target = '"/purchases/:purchaseId/refund"'
pos = text.find(target)
if pos == -1:
    raise SystemExit("❌ could not find refund route")

sig = "async (request, reply) => {"
k = text.find(sig, pos)
if k == -1:
    raise SystemExit("❌ could not find refund handler signature")

block_start = text.find("{", k)
if block_start == -1:
    raise SystemExit("❌ could not find opening { for refund handler")

# brace match refund handler block
depth = 0
end = None
for i in range(block_start, len(text)):
    ch = text[i]
    if ch == "{":
        depth += 1
    elif ch == "}":
        depth -= 1
        if depth == 0:
            end = i + 1
            break
if end is None:
    raise SystemExit("❌ could not find end of refund handler")

handler = text[block_start:end]
lines = handler.splitlines(True)

# Remove duplicate refundedByUserId lines, keep the first one we see.
out = []
seen = 0
for ln in lines:
    if "const refundedByUserId =" in ln:
        seen += 1
        if seen >= 2:
            # drop duplicates
            continue
        # normalize to preferred order: user?.id ?? user?.sub
        ln = "    const refundedByUserId = (request as any).user?.id ?? (request as any).user?.sub ?? null;\n"
    out.append(ln)

handler2 = "".join(out)

if seen == 0:
    # if missing entirely, add it near refundPaymentId line if present
    insert_after = "const refundPaymentId"
    idx = handler2.find(insert_after)
    if idx != -1:
        nl = handler2.find("\n", idx)
        handler2 = handler2[:nl+1] + "    const refundedByUserId = (request as any).user?.id ?? (request as any).user?.sub ?? null;\n" + handler2[nl+1:]
    else:
        # add after purchaseId line
        ins = handler2.find("const { purchaseId }")
        if ins != -1:
            nl = handler2.find("\n", ins)
            handler2 = handler2[:nl+1] + "    const refundedByUserId = (request as any).user?.id ?? (request as any).user?.sub ?? null;\n" + handler2[nl+1:]

# write back
new_text = text[:block_start] + handler2 + text[end:]
routes.write_text(new_text, encoding="utf-8")
print("✅ removed duplicate refundedByUserId (kept one)")
PY

echo "🔎 Typecheck..."
npx -y tsc -p "$ROOT/tsconfig.json" --noEmit
echo "✅ OK"
