#!/usr/bin/env bash
set -euo pipefail

PAYMENTS_FILE="src/routes/payments.ts"
WEBHOOKS_FILE="src/routes/webhooks.ts"
INDEX_FILE="src/routes/index.ts"

echo "== Fix duplicate POST /webhooks/paystack =="

# --- 1) Remove webhook route from payments.ts (keep webhooks.ts as the only source of truth)
if [[ -f "$PAYMENTS_FILE" ]]; then
  if grep -qE 'app\.post\(\s*["'\'']/webhooks/paystack["'\'']' "$PAYMENTS_FILE"; then
    cp -a "$PAYMENTS_FILE" "$PAYMENTS_FILE.bak"
    python3 - <<'PY'
from pathlib import Path

path = Path("src/routes/payments.ts")
s = path.read_text(encoding="utf-8")

needle = 'app.post("/webhooks/paystack"'
needle2 = "app.post('/webhooks/paystack'"

idx = s.find(needle)
if idx == -1:
  idx = s.find(needle2)

if idx == -1:
  print("No webhook route found in payments.ts (nothing to remove).")
  raise SystemExit(0)

# remove from the start of the line containing app.post('/webhooks/paystack'...) up to the matching close '});'
start = s.rfind("\n", 0, idx) + 1

# naive brace/paren aware scan until we hit a line that ends the handler
# We'll stop at the first occurrence after idx of '\n  );' or '\n});' pattern.
end = None

# Most common patterns:
# app.post(..., async (...) => { ... });
# app.post(..., async (...) => { ... })
# We'll find the first '});' that closes the app.post call after idx.
end_candidates = []
for token in ["\n});", "\n  });", "\n});\n", "\n  });\n", "\n    });", "\n    });\n"]:
    j = s.find(token, idx)
    if j != -1:
        end_candidates.append(j + len(token))

if not end_candidates:
    # fallback: first ');' after idx
    j = s.find(");", idx)
    if j != -1:
        end = j + 2
else:
    end = min(end_candidates)

if end is None:
    raise SystemExit("Could not safely find end of webhook route block in payments.ts")

new_s = s[:start] + s[end:]
path.write_text(new_s, encoding="utf-8")
print("✅ Removed duplicate /webhooks/paystack route from src/routes/payments.ts")
PY
  else
    echo "-> No /webhooks/paystack route in $PAYMENTS_FILE (ok)"
  fi
else
  echo "-> $PAYMENTS_FILE not found (skipping)"
fi

# --- 2) Ensure webhooks.ts exists (the route should live here)
if [[ ! -f "$WEBHOOKS_FILE" ]]; then
  echo "❌ $WEBHOOKS_FILE not found. You need a single webhook route file to keep."
  exit 1
fi

# --- 3) Ensure routes/index.ts registers webhooksRoutes once
if [[ -f "$INDEX_FILE" ]]; then
  cp -a "$INDEX_FILE" "$INDEX_FILE.bak"
  python3 - <<'PY'
from pathlib import Path
import re

path = Path("src/routes/index.ts")
s = path.read_text(encoding="utf-8")

# Add import if missing
if not re.search(r'from\s+[\'"]\.\/webhooks(\.js)?[\'"]', s):
    # Insert after last import line
    m = list(re.finditer(r'^\s*import .*?;\s*$', s, flags=re.M))
    if m:
        insert_at = m[-1].end()
        s = s[:insert_at] + '\nimport { webhooksRoutes } from "./webhooks.js";\n' + s[insert_at:]
    else:
        s = 'import { webhooksRoutes } from "./webhooks.js";\n' + s

# Ensure app.register(webhooksRoutes) exists only once
count = len(re.findall(r'\bapp\.register\(\s*webhooksRoutes\s*\)', s))
if count == 0:
    # Try to inject inside exported registerRoutes function
    # Find "export async function registerRoutes(app" or similar
    fn = re.search(r'export\s+async\s+function\s+registerRoutes\s*\(\s*app[^)]*\)\s*\{', s)
    if fn:
        insert_at = fn.end()
        s = s[:insert_at] + '\n  await app.register(webhooksRoutes);\n' + s[insert_at:]
    else:
        # fallback: append at end with comment
        s += '\n\n// register webhooks\n// eslint-disable-next-line @typescript-eslint/no-floating-promises\napp.register(webhooksRoutes);\n'
elif count > 1:
    # Remove duplicates leaving the first
    first = True
    def repl(m):
        nonlocal first
        if first:
            first = False
            return m.group(0)
        return ''
    s = re.sub(r'^\s*await\s+app\.register\(\s*webhooksRoutes\s*\);\s*$',
               lambda m: repl(m), s, flags=re.M)
    s = re.sub(r'^\s*app\.register\(\s*webhooksRoutes\s*\);\s*$',
               lambda m: repl(m), s, flags=re.M)

path.write_text(s, encoding="utf-8")
print("✅ Ensured src/routes/index.ts registers webhooksRoutes once")
PY
else
  echo "-> $INDEX_FILE not found (skipping registration patch)"
fi

echo ""
echo "Now verify duplicates are gone:"
echo "  grep -RIn --exclude-dir=node_modules --exclude='*.bak*' '/webhooks/paystack' src"
echo ""
echo "Then run:"
echo "  npm run typecheck 2>/dev/null || npx tsc -p tsconfig.json --noEmit"
echo "  npm run dev"
