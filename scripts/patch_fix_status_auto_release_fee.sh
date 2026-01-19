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

path = os.environ.get("FILE_PATH", "src/routes/purchases.routes.ts")
s = open(path, "r", encoding="utf-8").read()
orig = s

# We patch ONLY the auto-release call inside: if (newStatus === "closed") { ... purchase_escrow_release(... platformFeeAmount ... ) }
# Insert fee computation right before the purchase_escrow_release() call, and replace platformFeeAmount with platformFeeAmountAuto.

pattern = re.compile(
  r"""
  (if\s*\(newStatus\s*===\s*["']closed["']\)\s*\{[\s\S]*?
    if\s*\(held\s*>\s*alreadyReleased\)\s*\{\s*
  )
  (await\s+client\.query\(\s*
    `select\s+public\.purchase_escrow_release\([\s\S]*?\);\s*`,\s*
    \[purchaseId,\s*orgId,\s*held,\s*refreshed\.currency,\s*)platformFeeAmount(\s*,\s*note\s*\?\?\s*["']auto escrow release["']\]\s*\)\s*;)
  """,
  re.X
)

def repl(m):
  before = m.group(1)
  call_start = m.group(2)
  call_end = m.group(4)

  insert = """
                // ✅ Server-side platform fee for auto-close release
                // Fee should apply to the RELEASE DELTA (held - alreadyReleased)
                const releaseDelta = Math.max(0, held - alreadyReleased);
                const split = computePlatformFeeSplit({
                  paymentKind: "buy",
                  amount: releaseDelta,
                  currency: refreshed.currency,
                });
                const platformFeeAmountAuto = Number(split.platformFee ?? 0);

                // (optional) keep client-provided fee only for debugging
                void platformFeeAmountFromClient;

"""

  return before + insert + call_start + "platformFeeAmountAuto" + call_end

s2, n = pattern.subn(repl, s, count=1)

if n == 0:
  print("[ABORT] Pattern not found. Maybe already fixed or code changed.")
else:
  open(path, "w", encoding="utf-8").write(s2)
  print("✅ Patched status route auto-release to compute platform fee server-side.")

PY

echo "DONE ✅"
