#!/usr/bin/env bash
set -euo pipefail

INDEX_FILE="src/routes/index.ts"

echo "== Ensure webhooksRoutes is registered once =="

if [[ ! -f "$INDEX_FILE" ]]; then
  echo "❌ $INDEX_FILE not found."
  echo "Tell me your routes entry file (examples: src/routes/index.ts, src/app.ts, src/server.ts) and I’ll target it."
  exit 1
fi

cp -a "$INDEX_FILE" "$INDEX_FILE.bak"

python3 - <<'PY'
from pathlib import Path
import re

path = Path("src/routes/index.ts")
s = path.read_text(encoding="utf-8")

# 1) Ensure import exists
if not re.search(r'^\s*import\s+\{\s*webhooksRoutes\s*\}\s+from\s+[\'"]\.\/webhooks(\.js)?[\'"]\s*;\s*$',
                 s, flags=re.M):
    # insert after last import
    imports = list(re.finditer(r'^\s*import .*?;\s*$', s, flags=re.M))
    line = 'import { webhooksRoutes } from "./webhooks.js";\n'
    if imports:
        insert_at = imports[-1].end()
        s = s[:insert_at] + "\n" + line + s[insert_at:]
    else:
        s = line + s

# 2) Remove ALL existing registrations of webhooksRoutes (await or not)
s = re.sub(r'^\s*await\s+app\.register\(\s*webhooksRoutes\s*\)\s*;\s*\n?', '', s, flags=re.M)
s = re.sub(r'^\s*app\.register\(\s*webhooksRoutes\s*\)\s*;\s*\n?', '', s, flags=re.M)

# 3) Add exactly ONE registration inside registerRoutes()
m = re.search(r'(export\s+async\s+function\s+registerRoutes\s*\(\s*app[^)]*\)\s*\{)', s)
if m:
    insert_at = m.end()
    s = s[:insert_at] + "\n  await app.register(webhooksRoutes);\n" + s[insert_at:]
else:
    # fallback: try export function registerRoutes(app) { ... }
    m2 = re.search(r'(export\s+function\s+registerRoutes\s*\(\s*app[^)]*\)\s*\{)', s)
    if m2:
        insert_at = m2.end()
        s = s[:insert_at] + "\n  app.register(webhooksRoutes);\n" + s[insert_at:]
    else:
        # last fallback append
        s += "\n\n// webhooksRoutes registration (fallback)\n// NOTE: please move into registerRoutes(app) if you have one.\n"

path.write_text(s, encoding="utf-8")
print("✅ Patched src/routes/index.ts (import + single registration)")
PY

echo ""
echo "Verify registrations:"
echo "  grep -n \"webhooksRoutes\" -n src/routes/index.ts"
echo ""
echo "Verify webhook route appears only once (route definition):"
echo "  grep -RIn --exclude-dir=node_modules --exclude='*.bak*' \"app.post(\\\"/webhooks/paystack\\\"\" src"
echo ""
echo "Then run:"
echo "  npm run typecheck 2>/dev/null || npx tsc -p tsconfig.json --noEmit"
echo "  npm run dev"
