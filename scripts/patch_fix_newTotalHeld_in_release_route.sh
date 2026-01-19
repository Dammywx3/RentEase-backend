#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FILE="src/routes/purchases.routes.ts"
TS="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$ROOT/.patch_backups/$TS"
mkdir -p "$BACKUP_DIR"

echo "Repo: $ROOT"
echo "Backups: $BACKUP_DIR"
echo "Patching: $FILE"

[ -f "$FILE" ] || { echo "❌ Missing: $FILE"; exit 1; }

cp -a "$FILE" "$BACKUP_DIR/${FILE//\//__}"
echo "✅ Backup saved"

python3 - "$FILE" <<'PY'
import sys, pathlib, re

p = pathlib.Path(sys.argv[1])
s = p.read_text(encoding="utf-8")
orig = s

# Remove the accidental newTotalHeld lines that were inserted into the ESCROW RELEASE handler.
# We target the specific 2-line block.
pattern = r"""
^\s*const\s+currentHeld\s*=\s*Number\(\(purchase\s+as\s+any\)\?\.\s*escrow_held_amount\s*\?\?\s*0\);\s*\n
^\s*newTotalHeld\s*=\s*currentHeld\s*\+\s*amount;\s*\n
"""
s2 = re.sub(pattern, "", s, flags=re.MULTILINE | re.VERBOSE)

if s2 == orig:
    raise SystemExit("[ABORT] Pattern not found (maybe already fixed).")

p.write_text(s2, encoding="utf-8")
print("[OK] Removed bad newTotalHeld block from release route.")
PY

echo "✅ Done."
echo "Now run:"
echo "  rg -n \"newTotalHeld\" src/routes/purchases.routes.ts"