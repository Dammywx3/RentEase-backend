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

# ---- 1) Replace the arg only in the auto escrow release array line ----
# We target ONLY the array that contains: note ?? "auto escrow release"
s2, n1 = re.subn(
  r'(\[\s*purchaseId\s*,\s*orgId\s*,\s*held\s*,\s*refreshed\.currency\s*,\s*)platformFeeAmount(\s*,\s*note\s*\?\?\s*"auto escrow release"\s*\])',
  r'\1platformFeeAmountAuto\2',
  s
)

if n1 == 0:
  print("[ABORT] Could not find the auto escrow release argument array line to replace.")
  raise SystemExit(0)

# ---- 2) Ensure platformFeeAmountAuto is computed in-scope before the call ----
# Find the specific client.query call that ends with note ?? "auto escrow release"
call_pat = re.compile(
  r'^\s*await\s+client\.query\(\s*$.*?^.*?note\s*\?\?\s*"auto escrow release".*?$',
  re.M | re.S
)
m = call_pat.search(s2)
if not m:
  # We already replaced the array line; still try insertion by locating the array line index
  # and walking up to nearest 'await client.query('.
  lines = s2.splitlines(True)
  idx = None
  for i, line in enumerate(lines):
    if 'note ?? "auto escrow release"' in line and "purchaseId" in line and "held" in line:
      idx = i
      break
  if idx is None:
    print("[ABORT] Could not locate the auto escrow release section for inserting platformFeeAmountAuto.")
    raise SystemExit(0)

  # walk upward to find the await client.query that calls purchase_escrow_release
  j = idx
  found = None
  while j >= 0 and idx - j < 80:
    if "await client.query" in lines[j] and "purchase_escrow_release" in "".join(lines[j:j+6]):
      found = j
      break
    j -= 1
  if found is None:
    print("[ABORT] Could not find the purchase_escrow_release await call near the auto escrow release args.")
    raise SystemExit(0)

  insert_line = found
else:
  # insertion point = start line of that await call
  lines = s2.splitlines(True)
  # compute line number by counting newlines before match start
  insert_line = s2[:m.start()].count("\n")
  # insert before the line that begins the await call
  # (we’ll still use lines list for a clean insertion)
  # insert_line is already correct

# Check if platformFeeAmountAuto already exists in the local area above insertion
lines = s2.splitlines(True)
start = max(0, insert_line - 120)
window = "".join(lines[start:insert_line])
needs_insert = "platformFeeAmountAuto" not in window

snippet = """\
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

if needs_insert:
  lines.insert(insert_line, snippet)

out = "".join(lines)
open(path, "w", encoding="utf-8").write(out)

print("✅ Patched: auto escrow release now uses platformFeeAmountAuto (and computes it in-scope).")
PY

echo "DONE ✅"
