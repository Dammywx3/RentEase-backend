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
echo "✅ Backup -> $BACKUP_DIR"

python3 - <<'PY'
import os, re

path = os.environ.get("FILE_PATH","src/routes/purchases.routes.ts")
s = open(path, "r", encoding="utf-8").read()
orig = s

# 1) Replace the arg inside the purchase_escrow_release call that includes "auto escrow release"
# We specifically match the argument array portion to avoid touching other places.
arg_pat = re.compile(
  r"""
  (await\s+client\.query\(\s*`select\s+public\.purchase_escrow_release\([\s\S]*?\);\s*`,\s*\[
    \s*purchaseId\s*,\s*orgId\s*,\s*held\s*,\s*refreshed\.currency\s*,\s*)
  (platformFeeAmount|platformFeeAmountFromClient|platformFeeAmountAuto)
  (\s*,\s*note\s*\?\?\s*["']auto\sescr ow\ srelease["']\s*\]\s*\)\s*;)
  """.replace("escr ow","escrow"),
  re.X
)

m = arg_pat.search(s)
if not m:
  print("[ABORT] Could not find the auto escrow release DB call with expected args.")
  raise SystemExit(0)

# 2) Ensure the platformFeeAmountAuto computation exists in the same block above the call.
# We'll insert it immediately before the matched 'await client.query(' line,
# but only if platformFeeAmountAuto isn't already present nearby.
insert_snippet = """
                // ✅ Server-side platform fee for auto-close release (do NOT trust client)
                // Fee applies to the RELEASE DELTA (held - alreadyReleased)
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

call_start = m.start(1)
# look back a bit to see if we already inserted it
window_start = max(0, call_start - 1200)
window = s[window_start:call_start]

needs_insert = ("platformFeeAmountAuto" not in window)

# Replace arg variable to platformFeeAmountAuto
s2 = s[:m.start()] + (m.group(1) + "platformFeeAmountAuto" + m.group(3)) + s[m.end():]

# Insert snippet if needed
if needs_insert:
  # insert right before the 'await client.query(' line we matched
  # find the exact start of that line
  insert_at = s2.rfind("\n", 0, call_start) + 1
  s2 = s2[:insert_at] + insert_snippet + s2[insert_at:]

open(path, "w", encoding="utf-8").write(s2)
print("✅ Patched: auto escrow release now uses platformFeeAmountAuto (and computes it in-scope).")
PY

echo "DONE ✅"
