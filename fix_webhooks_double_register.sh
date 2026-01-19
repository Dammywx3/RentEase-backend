#!/usr/bin/env bash
set -euo pipefail

FILE="src/routes/index.ts"

echo "== Fix duplicate webhooksRoutes registration =="

if [[ ! -f "$FILE" ]]; then
  echo "❌ $FILE not found"
  exit 1
fi

cp -a "$FILE" "$FILE.bak"

python3 - <<'PY'
from pathlib import Path
import re

path = Path("src/routes/index.ts")
s = path.read_text(encoding="utf-8")

# 1) Ensure import exists (keep it once)
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

# 2) Remove EVERY registration line anywhere
s = re.sub(r'^\s*await\s+app\.register\(\s*webhooksRoutes\s*\)\s*;\s*\n?', '', s, flags=re.M)
s = re.sub(r'^\s*app\.register\(\s*webhooksRoutes\s*\)\s*;\s*\n?', '', s, flags=re.M)

# 3) Insert exactly one inside registerRoutes() right after the opening brace
m = re.search(r'(export\s+async\s+function\s+registerRoutes\s*\(\s*app[^)]*\)\s*\{)', s)
if m:
    insert_at = m.end()
    s = s[:insert_at] + "\n  await app.register(webhooksRoutes);\n" + s[insert_at:]
else:
    m2 = re.search(r'(export\s+function\s+registerRoutes\s*\(\s*app[^)]*\)\s*\{)', s)
    if m2:
        insert_at = m2.end()
        s = s[:insert_at] + "\n  app.register(webhooksRoutes);\n" + s[insert_at:]
    else:
        raise SystemExit("❌ Could not find registerRoutes(app) function in src/routes/index.ts")

path.write_text(s, encoding="utf-8")
print("✅ Fixed: webhooksRoutes now registered exactly once (inside registerRoutes)")
PY

echo ""
echo "Check result:"
grep -n "webhooksRoutes" "$FILE" || true

echo ""
echo "Now verify only ONE route definition exists:"
grep -RIn --exclude-dir=node_modules --exclude='*.bak*' 'app.post("/webhooks/paystack"' src || true

echo ""
echo "Then run:"
echo "  npm run dev"
