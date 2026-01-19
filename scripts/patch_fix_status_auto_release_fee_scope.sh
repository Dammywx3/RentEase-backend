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
echo "✅ Backup saved -> $BACKUP_DIR"

python3 - <<'PY'
import os, re

path = os.environ.get("FILE_PATH","src/routes/purchases.routes.ts")
s = open(path, "r", encoding="utf-8").read()
orig = s

# Target: inside status route (autoEscrow + newStatus === "closed") block:
# find the escrow release call that uses "held" and "refreshed.currency"
# ensure platformFeeAmountAuto is computed in-scope right before the call
# and replace platformFeeAmount argument with platformFeeAmountAuto.

pat = re.compile(
  r"""
  (if\s*\(\s*held\s*>\s*alreadyReleased\s*\)\s*\{\s*)
  ([\s\S]*?)
  (await\s+client\.query\(\s*`select\s+public\.purchase_escrow_release\([\s\S]*?\);\s*`,\s*
   \[purchaseId,\s*orgId,\s*held,\s*refreshed\.currency,\s*)
  (platformFeeAmount|platformFeeAmountAuto)
  (\s*,\s*note\s*\?\?\s*["']auto escrow release["']\s*\]\s*\)\s*;\s*)
  """,
  re.X
)

m = pat.search(s)
if not m:
  print("[ABORT] Could not find the auto-close escrow release block/call. Code may have changed.")
  raise SystemExit(0)

before = m.group(1)
middle = m.group(2)
call_start = m.group(3)
call_end = m.group(5)

# Avoid inserting twice
if "platformFeeAmountAuto" in middle:
  insert = ""
else:
  insert = """
                // ✅ Server-side platform fee for auto-close release (do NOT trust client)
                // Fee should apply to the RELEASE DELTA (held - alreadyReleased)
                const releaseDelta = Math.max(0, held - alreadyReleased);
                const splitAuto = computePlatformFeeSplit({
                  paymentKind: "buy",
                  amount: releaseDelta,
                  currency: refreshed.currency,
                });
                const platformFeeAmountAuto = Number(splitAuto.platformFee ?? 0);

                // (optional) keep client fee for debugging only
                void platformFeeAmountFromClient;

"""

replacement = before + middle + insert + call_start + "platformFeeAmountAuto" + call_end
s2 = s[:m.start()] + replacement + s[m.end():]

open(path, "w", encoding="utf-8").write(s2)
print("✅ Patched: auto-close escrow release now uses platformFeeAmountAuto (in-scope).")
PY

echo "DONE ✅"

