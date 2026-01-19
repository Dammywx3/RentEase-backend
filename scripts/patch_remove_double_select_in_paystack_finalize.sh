#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FILE="src/services/paystack_finalize.service.ts"
TS="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$ROOT/.patch_backups/$TS"
mkdir -p "$BACKUP_DIR"

echo
echo "Repo: $ROOT"
echo "Backups: $BACKUP_DIR"
echo "Target: $FILE"

[ -f "$FILE" ] || { echo "❌ Missing: $FILE"; exit 1; }

cp -a "$FILE" "$BACKUP_DIR/${FILE//\//__}"
echo "✅ Backup saved"

python3 - "$FILE" <<'PY'
import sys, pathlib, re

p = pathlib.Path(sys.argv[1])
s = p.read_text(encoding="utf-8")
orig = s

# Replace "select\nselect" (with any whitespace) -> "select"
s = re.sub(r"(?im)(^\s*select\s*$\n)\s*select\s*$\n", r"\1", s)

if s == orig:
    print("[OK] No double-select patterns found. Nothing changed.")
else:
    p.write_text(s, encoding="utf-8")
    print("[OK] Removed double-select occurrences.")
PY

echo "Done."
echo "Check:"
echo "  sed -n '250,290p' $FILE"