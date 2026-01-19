#!/usr/bin/env bash
set -euo pipefail

FILE="${FILE_PATH:-src/routes/purchases.routes.ts}"

if [ ! -f "$FILE" ]; then
  echo "❌ File not found: $FILE"
  exit 1
fi

TS=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR=".patch_backups/${TS}"
mkdir -p "$BACKUP_DIR"

# backup
cp "$FILE" "$BACKUP_DIR/$(echo "$FILE" | tr '/.' '__')"
echo "✅ Backup: $FILE -> $BACKUP_DIR/$(echo "$FILE" | tr '/.' '__')"

python3 - <<'PY'
import os, re

path = os.environ.get("FILE_PATH", "src/routes/purchases.routes.ts")
txt = open(path, "r", encoding="utf-8").read()
orig = txt

# 1) Remove any standalone "\1" artifact lines inserted by the patch.
txt = re.sub(r'(?m)^[ \t]*\\1[ \t]*\r?\n', '', txt)

# 2) Re-apply intended formatting safely (NO backreference text leak).
# Ensure blank line after: await assertRlsContextWithUser(client);
txt = re.sub(
    r"(await assertRlsContextWithUser\(client\);\s*)const purchase =",
    r"\g<1>\n        const purchase =",
    txt
)

if txt == orig:
    print("[ABORT] No changes applied (maybe already fixed).")
else:
    open(path, "w", encoding="utf-8").write(txt)
    print("✅ Removed '\\1' artifacts and restored spacing.")
PY

echo "DONE ✅"
