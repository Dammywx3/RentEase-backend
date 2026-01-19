#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROUTES="$ROOT/src/routes/purchases.routes.ts"

[ -f "$ROUTES" ] || { echo "❌ Not found: $ROUTES"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$ROOT/scripts/.bak"
cp "$ROUTES" "$ROOT/scripts/.bak/purchases.routes.ts.bak.trim.$TS"
echo "✅ backup -> scripts/.bak/purchases.routes.ts.bak.trim.$TS"

export ROUTES

python3 - <<'PY'
from pathlib import Path
import os, re, sys

p = Path(os.environ["ROUTES"])
s = p.read_text(encoding="utf-8")

# Find the exported function start
m = re.search(r'export\s+default\s+async\s+function\s+purchasesRoutes\s*\([^)]*\)\s*\{', s)
if not m:
    print("❌ Could not find purchasesRoutes() export.", file=sys.stderr)
    sys.exit(1)

start = m.end() - 1  # points at the '{' of the function

# Lightweight TS brace matching, skipping strings/comments/template literals.
i = start
depth = 0
in_sq = in_dq = in_bt = False
in_line_comment = False
in_block_comment = False
escape = False

while i < len(s):
    ch = s[i]
    nxt = s[i+1] if i+1 < len(s) else ""

    # Handle comments
    if in_line_comment:
        if ch == "\n":
            in_line_comment = False
        i += 1
        continue

    if in_block_comment:
        if ch == "*" and nxt == "/":
            in_block_comment = False
            i += 2
            continue
        i += 1
        continue

    # Enter comments (only if not in string/template)
    if not (in_sq or in_dq or in_bt):
        if ch == "/" and nxt == "/":
            in_line_comment = True
            i += 2
            continue
        if ch == "/" and nxt == "*":
            in_block_comment = True
            i += 2
            continue

    # Handle escaping inside strings/templates
    if (in_sq or in_dq or in_bt) and escape:
        escape = False
        i += 1
        continue
    if (in_sq or in_dq or in_bt) and ch == "\\":
        escape = True
        i += 1
        continue

    # Toggle string/template states
    if not (in_dq or in_bt) and ch == "'" and not in_sq:
        in_sq = True
        i += 1
        continue
    if in_sq and ch == "'":
        in_sq = False
        i += 1
        continue

    if not (in_sq or in_bt) and ch == '"' and not in_dq:
        in_dq = True
        i += 1
        continue
    if in_dq and ch == '"':
        in_dq = False
        i += 1
        continue

    if not (in_sq or in_dq) and ch == "`" and not in_bt:
        in_bt = True
        i += 1
        continue
    if in_bt and ch == "`":
        in_bt = False
        i += 1
        continue

    # Only count braces when not in string/template
    if not (in_sq or in_dq or in_bt):
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                # Found the matching close brace of purchasesRoutes
                end = i + 1
                trimmed = s[:end].rstrip() + "\n"
                p.write_text(trimmed, encoding="utf-8")
                print("✅ Trimmed file to end of purchasesRoutes() (removed trailing tokens)")
                sys.exit(0)

    i += 1

print("❌ Did not find matching closing brace for purchasesRoutes().", file=sys.stderr)
sys.exit(1)
PY

echo "🔎 Typecheck..."
npx -y tsc -p "$ROOT/tsconfig.json" --noEmit
echo "✅ Typecheck passed"
