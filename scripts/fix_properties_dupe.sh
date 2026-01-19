#!/usr/bin/env bash
if [ "${BASH_SOURCE[0]}" != "$0" ]; then
  echo "❌ Don't source this. Run: bash scripts/fix_properties_dupe.sh"
  return 0 2>/dev/null || true
fi

set -u

FILE="src/routes/properties.ts"
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP="scripts/_backup_fix_properties_dupe_${STAMP}"
mkdir -p "$BACKUP"
cp "$FILE" "$BACKUP/$(basename "$FILE")"

echo "============================================================"
echo "Fix properties.ts: change 2nd app.get(\"/\") -> app.post(\"/\")"
echo "Backup: $BACKUP/$(basename "$FILE")"
echo "============================================================"
echo ""
echo "---- BEFORE ----"
rg -n 'app\.(get|post|put|patch|delete)\(' "$FILE" || true

python3 - <<'PY'
from pathlib import Path
p = Path("src/routes/properties.ts")
s = p.read_text(encoding="utf-8")

needle = 'app.get("/"'
idx1 = s.find(needle)
if idx1 == -1:
    print("❌ Did not find app.get(\"/\") at all.")
    raise SystemExit(1)

idx2 = s.find(needle, idx1 + len(needle))
if idx2 == -1:
    print("✅ Only one app.get(\"/\") found — no duplicate to fix.")
    raise SystemExit(0)

# Replace only the second occurrence
s2 = s[:idx2] + s[idx2:].replace(needle, 'app.post("/"', 1)
p.write_text(s2, encoding="utf-8")
print("✅ Replaced the 2nd app.get(\"/\") with app.post(\"/\")")
PY

echo ""
echo "---- AFTER ----"
rg -n 'app\.(get|post|put|patch|delete)\(' "$FILE" || true

echo ""
echo "---- CHECK duplicate GET / ----"
COUNT="$(rg -n 'app\.get\(\s*"\s*/\s*"' "$FILE" | wc -l | tr -d ' ')"
echo "GET / count = $COUNT"
if [ "$COUNT" -gt 1 ]; then
  echo "❌ Still duplicated. Restore backup from: $BACKUP"
  exit 1
else
  echo "✅ Fixed."
fi

echo "============================================================"
echo "Next:"
echo "  npm run build"
echo "  # restart server: Ctrl+C then npm run dev"
echo "============================================================"
