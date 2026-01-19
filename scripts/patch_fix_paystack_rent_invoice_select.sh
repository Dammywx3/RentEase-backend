#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# RentEase patch: fix duplicated "select select" in
# src/services/paystack_finalize.service.ts (rent_invoice payee query)
# ------------------------------------------------------------

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$ROOT/.patch_backups/$TS"
mkdir -p "$BACKUP_DIR"

say() { printf "\n\033[1m%s\033[0m\n" "$*"; }
ok()  { printf "✅ %s\n" "$*"; }
die() { printf "❌ %s\n" "$*"; exit 1; }

FILE="src/services/paystack_finalize.service.ts"
[[ -f "$FILE" ]] || die "Missing file: $FILE"

backup() {
  local f="$1"
  local dest="$BACKUP_DIR/${f//\//__}"
  cp -a "$f" "$dest"
  ok "Backup: $f -> $dest"
}

say "Repo: $ROOT"
say "Backups: $BACKUP_DIR"
say "Patching: $FILE"

backup "$FILE"

python3 - "$FILE" <<'PY'
import sys, pathlib, re

path = pathlib.Path(sys.argv[1])
src = path.read_text(encoding="utf-8")
orig = src

# 1) Fix the common exact bug: a stray duplicated 'select' line inside the template string
#    This targets patterns like:
#      `
#      select
#      select
#        p.owner_id...
#    and becomes:
#      `
#      select
#        p.owner_id...

src = re.sub(
    r"(`\s*\n\s*select\s*\n)\s*select\s*\n",
    r"\1",
    src,
    flags=re.IGNORECASE
)

# 2) Extra safety: if someone wrote "select\n      select\n" with indentation, catch that too
src = re.sub(
    r"(`\s*\n\s*select\s*\n)(\s*)select\s*\n",
    r"\1",
    src,
    flags=re.IGNORECASE
)

if src == orig:
    raise SystemExit("[ABORT] No changes applied. Either it's already fixed or pattern not found.")

path.write_text(src, encoding="utf-8")
print("[OK] Patched", path)
PY

ok "Done."
say "Tip: inspect diff:"
echo "  git diff -- $FILE  (if this repo is git)"
echo "Backups saved in: $BACKUP_DIR"