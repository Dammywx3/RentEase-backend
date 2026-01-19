#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
STAMP="$(date +%Y%m%d_%H%M%S)"
BAK_DIR="$ROOT/scripts/.bak"
mkdir -p "$BAK_DIR"

SERVER="$ROOT/src/server.ts"

if [[ ! -f "$SERVER" ]]; then
  echo "❌ Not found: $SERVER"
  exit 1
fi

cp -p "$SERVER" "$BAK_DIR/server.ts.bak.$STAMP"
echo "✅ backup -> $BAK_DIR/server.ts.bak.$STAMP"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("src/server.ts")
t = p.read_text(encoding="utf-8")

# Remove the entire injected block starting from the marker to the end of the addHook call.
pat = re.compile(
    r"\n*// --- DB session context for RLS/audit triggers ---\nfastify\.addHook\(\s*[\"']preHandler[\"']\s*,\s*async\s*\(request\)\s*=>\s*\{.*?\}\);\s*\n*",
    re.DOTALL
)

new_t, n = pat.subn("\n", t, count=1)
if n == 0:
    # If someone changed spacing, remove any trailing top-level fastify.addHook('preHandler'...)
    pat2 = re.compile(
        r"\n*fastify\.addHook\(\s*[\"']preHandler[\"']\s*,\s*async\s*\(request\)\s*=>\s*\{.*?\}\);\s*\n*",
        re.DOTALL
    )
    new_t, n = pat2.subn("\n", t, count=1)

p.write_text(new_t, encoding="utf-8")
print(f"✅ Removed bad global hook blocks: {n}")
PY

echo "✅ server.ts fixed"
echo "Next: npm run dev"
