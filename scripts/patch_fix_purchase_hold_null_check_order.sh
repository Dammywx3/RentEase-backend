#!/usr/bin/env bash
set -euo pipefail

FILE="${FILE_PATH:-src/routes/purchases.routes.ts}"

if [ ! -f "$FILE" ]; then
  echo "[ERR] File not found: $FILE"
  exit 1
fi

ROOT="$(pwd)"
STAMP="$(date +%Y%m%d_%H%M%S)"
BKDIR="$ROOT/.patch_backups/$STAMP"
mkdir -p "$BKDIR"

cp "$FILE" "$BKDIR/$(echo "$FILE" | sed 's#/#__#g')"
echo "✅ Backup: $FILE -> $BKDIR/$(echo "$FILE" | sed 's#/#__#g')"

python3 - <<'PY'
import os, re

path = os.environ.get("FILE_PATH", "src/routes/purchases.routes.ts")
txt = open(path, "r", encoding="utf-8").read()

old = r"""const purchase = await fetchPurchaseOr404\(client, purchaseId, orgId\);
const currentHeld = Number\(\(purchase as any\)\?\.escrow_held_amount \?\? 0\);
        newTotalHeld = currentHeld \+ amount;
if \(!purchase\) \{
          await client\.query\("ROLLBACK"\);
          return reply\.code\(404\)\.send\(\{ ok: false, error: "NOT_FOUND", message: "Purchase not found" \}\);
        \}
"""

new = """const purchase = await fetchPurchaseOr404(client, purchaseId, orgId);
        if (!purchase) {
          await client.query("ROLLBACK");
          return reply.code(404).send({ ok: false, error: "NOT_FOUND", message: "Purchase not found" });
        }

        const currentHeld = Number((purchase as any)?.escrow_held_amount ?? 0);
        newTotalHeld = currentHeld + amount;
"""

if not re.search(old, txt, flags=re.M):
    raise SystemExit("[ABORT] Pattern not found (maybe already fixed or spacing differs).")

txt2 = re.sub(old, new, txt, flags=re.M)
open(path, "w", encoding="utf-8").write(txt2)
print("✅ Patch applied (hold route null-check ordering fixed).")
PY

echo "✅ Done."
