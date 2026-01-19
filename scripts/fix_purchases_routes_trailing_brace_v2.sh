#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE="$ROOT/src/routes/purchases.routes.ts"

[ -f "$FILE" ] || { echo "❌ Not found: $FILE"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$ROOT/scripts/.bak"
cp "$FILE" "$ROOT/scripts/.bak/purchases.routes.ts.bak.$TS"
echo "✅ backup -> scripts/.bak/purchases.routes.ts.bak.$TS"

echo ""
echo "==> BEFORE (tail -n 50)"
nl -ba "$FILE" | tail -n 50

# Export path so Python can read it without bash interpolation issues
export ROUTES_FILE="$FILE"

python3 - <<'PY'
import os, re
from pathlib import Path

path = os.environ.get("ROUTES_FILE")
if not path:
    raise SystemExit("❌ ROUTES_FILE env var missing")

p = Path(path)
t = p.read_text(encoding="utf-8")

# Anchor: find the LAST occurrence of "client.release();" (should be in the refund handler)
idx = t.rfind("client.release();")
if idx == -1:
    raise SystemExit("❌ Could not find 'client.release();' to anchor trimming.")

# Find the next occurrence of "});" after that (close of fastify.post handler)
close_pos = t.find("});", idx)
if close_pos == -1:
    raise SystemExit("❌ Could not find closing '});' after the last client.release().")

keep = t[:close_pos + 3].rstrip() + "\n\n}\n"
p.write_text(keep, encoding="utf-8")

print("✅ Trimmed trailing garbage and enforced file ending.")
PY

echo ""
echo "==> AFTER (tail -n 50)"
nl -ba "$FILE" | tail -n 50

echo ""
echo "�� Typecheck..."
npx -y tsc -p "$ROOT/tsconfig.json" --noEmit
echo "✅ OK"
