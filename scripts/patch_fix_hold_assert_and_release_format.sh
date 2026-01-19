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
cp "$FILE" "$BACKUP_DIR/$(echo "$FILE" | tr '/.' '__')"
echo "✅ Backup: $FILE -> $BACKUP_DIR/$(echo "$FILE" | tr '/.' '__')"

python3 - <<'PY'
import os, re

path = os.environ.get("FILE_PATH", "src/routes/purchases.routes.ts")
txt = open(path, "r", encoding="utf-8").read()
orig = txt

# ----------------------------
# A) HOLD route: add assertRlsContextWithUser right after setPgContext
# ----------------------------
hold_anchor = '"/:purchaseId/escrow/hold"'
m = re.search(re.escape(hold_anchor), txt)
if not m:
    raise SystemExit("❌ Could not find hold route anchor")

# Work on the region after the hold anchor only
start = m.start()
head = txt[:start]
tail = txt[start:]

# Insert assert only if the next fetchPurchaseOr404 comes without it
def insert_assert_after_setpg(segment: str) -> str:
    # find first setPgContext(...) followed by fetchPurchaseOr404 in this segment
    pat = re.compile(
        r'(await setPgContext\(client,\s*\{\s*[\s\S]*?\}\);\s*\n)'
        r'(\s*)(?!await assertRlsContextWithUser\(client\);\s*\n)'
        r'(const purchase = await fetchPurchaseOr404\(client, purchaseId, orgId\);)',
        re.M
    )
    return pat.sub(r'\1\2await assertRlsContextWithUser(client);\n\2\3', segment, count=1)

tail2 = insert_assert_after_setpg(tail)
txt = head + tail2

# ----------------------------
# B) RELEASE route: clean var block (ensure note newline, remove early duplicate void)
# ----------------------------
# Fix the ugly block where void is before const note / missing newline
txt = re.sub(
    r'(const platformFeeAmountFromClient\s*=\s*Number\(request\.body\.platformFeeAmount\s*\?\?\s*0\);\s*)\n\s*void platformFeeAmountFromClient;\s*\n\s*const note\s*=',
    r'\1\n\n      const note =',
    txt,
    count=1
)

# Also normalize any accidental "void ...;const note" glue
txt = re.sub(
    r'void platformFeeAmountFromClient;\s*const note\s*=',
    r'void platformFeeAmountFromClient;\n      const note =',
    txt,
    count=1
)

changed = (txt != orig)
if not changed:
    print("[ABORT] No changes applied (already fixed or patterns not found).")
else:
    open(path, "w", encoding="utf-8").write(txt)
    print("✅ Patched: hold route now asserts RLS; release route formatting cleaned.")
PY

echo "DONE ✅"
