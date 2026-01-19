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
# 1) HOLD ROUTE: ensure assert exists right after setPgContext
# ----------------------------
# Find the hold handler block by anchor text and patch the first occurrence.
hold_anchor = r'"/:purchaseId/escrow/hold"'
m = re.search(hold_anchor, txt)
if not m:
    raise SystemExit("❌ Could not find hold route anchor")

# Insert assert after setPgContext(...) in hold route (only if missing immediately after)
txt = re.sub(
    r'(\n\s*await setPgContext\(client,\s*\{\s*[\s\S]*?\}\);\s*\n)(\s*)(const purchase = await fetchPurchaseOr404)',
    lambda mm: mm.group(1) + f"{mm.group(2)}await assertRlsContextWithUser(client);\n{mm.group(2)}" + mm.group(3)
    if "assertRlsContextWithUser" not in mm.group(1) else mm.group(0),
    txt,
    count=1
)

# Remove the accidental duplicated block inside hold route:
# It starts right after "newTotalHeld = currentHeld + amount;" and repeats timezone+setPgContext+fetchPurchase.
txt = re.sub(
    r'(\n\s*newTotalHeld\s*=\s*currentHeld\s*\+\s*amount;\s*\n)'
    r'(\s*await client\.query\("SET LOCAL TIME ZONE \'UTC\'"\);\s*\n'
    r'\s*await setPgContext\(client,\s*\{\s*[\s\S]*?\}\);\s*\n'
    r'\s*(?:await assertRlsContextWithUser\(client\);\s*\n)?'
    r'\s*const purchase = await fetchPurchaseOr404\(client, purchaseId, orgId\);\s*\n)',
    r'\1',
    txt,
    count=1
)

# ----------------------------
# 2) RELEASE ROUTE: ensure assert exists right after setPgContext
# ----------------------------
release_anchor = r'"/:purchaseId/escrow/release"'
m2 = re.search(release_anchor, txt)
if not m2:
    raise SystemExit("❌ Could not find release route anchor")

# Insert assert after setPgContext(...) in release route (first occurrence after release anchor)
# We'll do a targeted substitution after the release anchor region.
start = m2.start()
tail = txt[start:]

tail2 = re.sub(
    r'(\n\s*await setPgContext\(client,\s*\{\s*[\s\S]*?\}\);\s*\n)(\s*)(const purchase = await fetchPurchaseOr404)',
    lambda mm: mm.group(1) + f"{mm.group(2)}await assertRlsContextWithUser(client);\n{mm.group(2)}" + mm.group(3)
    if "assertRlsContextWithUser" not in mm.group(1) else mm.group(0),
    tail,
    count=1
)

txt = txt[:start] + tail2

# ----------------------------
# 3) Minor formatting: ensure "if (!purchase)" line is indented in release route
# ----------------------------
txt = re.sub(r'\nif\s*\(!purchase\)\s*\{', r'\n        if (!purchase) {', txt)

changed = (txt != orig)
if not changed:
    print("[ABORT] No changes applied (already clean or patterns not found).")
else:
    open(path, "w", encoding="utf-8").write(txt)
    print("✅ Cleaned duplicate hold block + restored RLS assert in hold/release.")
PY

echo "DONE ✅"
