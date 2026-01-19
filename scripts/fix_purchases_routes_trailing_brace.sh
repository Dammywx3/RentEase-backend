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
echo "==> BEFORE (tail -n 40)"
nl -ba "$FILE" | tail -n 40

# Remove trailing garbage AFTER the refund route closure:
# Keep everything up to the FIRST occurrence of:
# "client.release();" ... "});"
# then ensure file ends with exactly one final "}".
python3 - <<'PY'
from pathlib import Path
import re

p = Path(r"""'"$FILE"'""")
t = p.read_text(encoding="utf-8")

# Find the refund route block end (we keep up to the "});" that closes the refund route)
m = re.search(r"(client\.release\(\);\s*\n\s*}\s*\n\s*\)\s*;\s*\n\s*}\s*\n\s*)", t)
# Above pattern might be too strict depending on earlier blocks; use a simpler anchor:
# Find last occurrence of "client.release();" inside refund route, then the next "});"
idx = t.rfind("client.release();")
if idx == -1:
    raise SystemExit("❌ Could not find 'client.release();' in file to anchor trimming.")

after = t[idx:]
m2 = re.search(r"client\.release\(\);\s*\n\s*}\s*\n\s*\)\s*;\s*", after)
# Not reliable; do next approach:
# Find the "});" that closes the refund route by searching forward from last client.release();
close_pos = t.find("});", idx)
if close_pos == -1:
    raise SystemExit("❌ Could not find refund route closing '});' after client.release().")

keep = t[:close_pos+3]  # include "});"

# Now strip any trailing whitespace and append "\n\n}\n"
keep = keep.rstrip() + "\n\n}\n"

p.write_text(keep, encoding="utf-8")
print("✅ Trimmed trailing garbage and enforced file ending.")
PY

echo ""
echo "==> AFTER (tail -n 40)"
nl -ba "$FILE" | tail -n 40

echo ""
echo "🔎 Typecheck..."
npx -y tsc -p "$ROOT/tsconfig.json" --noEmit
echo "✅ OK"
