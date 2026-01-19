#!/usr/bin/env bash
set -euo pipefail

FILE="src/routes/purchases.routes.ts"
if [ ! -f "$FILE" ]; then
  echo "❌ File not found: $FILE"
  exit 1
fi

TS=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR=".patch_backups/${TS}"
mkdir -p "$BACKUP_DIR"
cp "$FILE" "$BACKUP_DIR/src__routes__purchases.routes.ts"
echo "✅ Backup -> $BACKUP_DIR/src__routes__purchases.routes.ts"

python3 - <<'PY'
import re

path = "src/routes/purchases.routes.ts"
s = open(path, "r", encoding="utf-8").read()
orig = s

# ------------------------------------------------------------
# (1) REMOVE the wrongly injected "auto-close release fee" block
# that was inserted into the HOLD route.
# We remove the exact block starting at:
#   // ✅ Server-side platform fee for auto-close release ...
# down through:
#   void platformFeeAmountFromClient;
# ------------------------------------------------------------
bad_block = re.compile(
  r"\n\s*// ✅ Server-side platform fee for auto-close release \(do NOT trust client\)\n"
  r"\s*// Fee applies to the RELEASE DELTA \(held - alreadyReleased\)\n"
  r"\s*const releaseDelta = Math\.max\(0, held - alreadyReleased\);\n"
  r"\s*const splitAuto = computePlatformFeeSplit\(\{\n"
  r"\s*  paymentKind: \"buy\",\n"
  r"\s*  amount: releaseDelta,\n"
  r"\s*  currency: refreshed\.currency,\n"
  r"\s*\}\);\n"
  r"\s*const platformFeeAmountAuto = Number\(splitAuto\.platformFee \?\? 0\);\n"
  r"\n"
  r"\s*// \(optional\) keep client fee for debugging only\n"
  r"\s*void platformFeeAmountFromClient;\n",
  re.M
)

s, n_rm = bad_block.subn("\n", s)

# ------------------------------------------------------------
# (2) In STATUS auto-close block, your code computes:
#   const platformFeeAmount = ...
# but the query uses platformFeeAmountAuto.
# Replace platformFeeAmountAuto -> platformFeeAmount only in that call.
# ------------------------------------------------------------
s, n_fix = re.subn(
  r'(\[\s*purchaseId\s*,\s*orgId\s*,\s*held\s*,\s*refreshed\.currency\s*,\s*)platformFeeAmountAuto(\s*,\s*note\s*\?\?\s*"auto escrow release"\s*\])',
  r'\1platformFeeAmount\2',
  s
)

open(path, "w", encoding="utf-8").write(s)

print(f"✅ Removed bad hold-route block: {n_rm} occurrence(s)")
print(f"✅ Fixed auto-close release fee var: {n_fix} occurrence(s)")
PY

echo "DONE ✅"
