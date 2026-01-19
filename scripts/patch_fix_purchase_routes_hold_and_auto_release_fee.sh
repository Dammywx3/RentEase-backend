#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TS_FILE="src/routes/purchases.routes.ts"
if [ ! -f "$TS_FILE" ]; then
  echo "❌ File not found: $TS_FILE"
  exit 1
fi

STAMP="$(date +%Y%m%d_%H%M%S)"
BKDIR="$ROOT_DIR/.patch_backups/$STAMP"
mkdir -p "$BKDIR"
cp "$TS_FILE" "$BKDIR/$(echo "$TS_FILE" | sed 's#/#__#g')"
echo "✅ Backup: $TS_FILE -> $BKDIR"

python3 - <<'PY'
import re, pathlib, sys

path = pathlib.Path("src/routes/purchases.routes.ts")
s = path.read_text(encoding="utf-8")

orig = s

# ---------------------------
# 1) FIX /escrow/hold: compute newTotalHeld
# Look for pattern: const purchase = await fetchPurchaseOr404(...);
# and BEFORE calling purchase_escrow_hold, ensure:
#   const currentHeld = ...
#   newTotalHeld = currentHeld + amount;
# ---------------------------

# If newTotalHeld assignment exists, keep. If missing, inject.
hold_block_re = re.compile(
  r"(const purchase\s*=\s*await fetchPurchaseOr404\([^\)]*\);\s*[\r\n]+)(\s*if\s*\(!purchase\)\s*\{[\s\S]*?\}\s*[\r\n]+)",
  re.M
)

m = hold_block_re.search(s)
if m:
  inject = (
    m.group(1) +
    "        const currentHeld = Number((purchase as any)?.escrow_held_amount ?? 0);\n"
    "        newTotalHeld = currentHeld + amount;\n" +
    m.group(2)
  )
  s = s[:m.start()] + inject + s[m.end():]

# Also ensure we are not calling DB with newTotalHeld still 0 by mistake:
# If we find purchase_escrow_hold(...) with newTotalHeld, we are ok; if it uses 0, we replace.
s = re.sub(
  r"\[\s*purchaseId\s*,\s*orgId\s*,\s*0\s*,\s*purchase\.currency\s*,",
  "[purchaseId, orgId, newTotalHeld, purchase.currency,",
  s
)

# ---------------------------
# 2) FIX /status autoEscrow closed: platformFeeAmount is undefined
# Replace the purchase_escrow_release call args to compute platform fee server-side
# based on release delta (held - alreadyReleased).
# ---------------------------

# Find the auto-release call that currently passes platformFeeAmount
auto_release_re = re.compile(
  r"""
  (if\s*\(held\s*>\s*alreadyReleased\)\s*\{\s*\n\s*await\s+client\.query\(\s*\n\s*`select\s+public\.purchase_escrow_release\([^\`]*\);`,\s*\n\s*//\s*DB\s+function\s+expects\s+NEW\s+TOTAL\s+released\s*\n\s*\[purchaseId,\s*orgId,\s*held,\s*refreshed\.currency,\s*)(platformFeeAmount)(,\s*note\s*\?\?\s*"auto\s+escrow\s+release"\]\s*\)\s*;\s*\n\s*\})
  """,
  re.X
)

m2 = auto_release_re.search(s)
if m2:
  replacement = (
    "              if (held > alreadyReleased) {\n"
    "                const releaseDelta = held - alreadyReleased;\n"
    "                const split = computePlatformFeeSplit({\n"
    "                  paymentKind: \"buy\",\n"
    "                  amount: releaseDelta,\n"
    "                  currency: refreshed.currency,\n"
    "                });\n"
    "                const platformFeeAmount = Number(split.platformFee ?? 0);\n"
    "\n"
    "                await client.query(\n"
    "                  `select public.purchase_escrow_release($1::uuid, $2::uuid, $3::numeric, $4::text, $5::numeric, $6::text);`,\n"
    "                  // DB function expects NEW TOTAL released\n"
    "                  [purchaseId, orgId, held, refreshed.currency, platformFeeAmount, note ?? \"auto escrow release\"]\n"
    "                );\n"
    "              }"
  )
  s = s[:m2.start()] + replacement + s[m2.end():]

# If we changed nothing, exit with message
if s == orig:
  print("[ABORT] Pattern not found or already fixed.")
  sys.exit(0)

path.write_text(s, encoding="utf-8")
print("✅ Patched src/routes/purchases.routes.ts")
PY

echo "DONE ✅"
echo "Now run: npm run typecheck  (or npm run dev)"