#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FILE="src/routes/purchases.routes.ts"
TS="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$ROOT/.patch_backups/$TS"
mkdir -p "$BACKUP_DIR"

echo "Repo: $ROOT"
echo "Backups: $BACKUP_DIR"
echo "Patching: $FILE"

[ -f "$FILE" ] || { echo "❌ Missing: $FILE"; exit 1; }

cp -a "$FILE" "$BACKUP_DIR/${FILE//\//__}"
echo "✅ Backup saved"

python3 - "$FILE" <<'PY'
import sys, pathlib, re

p = pathlib.Path(sys.argv[1])
src = p.read_text(encoding="utf-8")
orig = src

# 1) Ensure fees import exists
if "computePlatformFeeSplit" not in src:
    # place near other imports at top
    src = src.replace(
        'import { refundPropertyPurchase } from "../services/purchase_refunds.service.js";',
        'import { refundPropertyPurchase } from "../services/purchase_refunds.service.js";\nimport { computePlatformFeeSplit } from "../config/fees.config.js";'
    )

# 2) In release route: remove reading platformFeeAmount from body (keep schema if you want, but ignore value)
# Replace the line that reads platformFeeAmount from body with a safe placeholder (we will compute later)
src = re.sub(
    r'const platformFeeAmount = Number\(request\.body\.platformFeeAmount \?\? 0\);\n',
    'const platformFeeAmountFromClient = Number(request.body.platformFeeAmount ?? 0);\n',
    src
)

# 3) After newTotalRelease is computed, compute fee server-side using DELTA amount
# We insert right after:
# const newTotalRelease = currentReleased + amount;
marker = "const newTotalRelease = currentReleased + amount;"
if marker in src and "computePlatformFeeSplit" in src:
    inject = """
        // ✅ Server-side fee (do NOT trust client for platform fees)
        // Fee is computed on the RELEASE DELTA (amount)
        const split = computePlatformFeeSplit({
          paymentKind: "buy",
          amount,
          currency: purchase.currency,
        });
        const platformFeeAmount = Number(split.platformFee ?? 0);

        // (optional) log/keep client value for debugging
        void platformFeeAmountFromClient;
"""
    if "const platformFeeAmount = Number(split.platformFee" not in src:
        src = src.replace(marker, marker + "\n" + inject)

# 4) Ensure the DB call uses platformFeeAmount (server-side variable)
# (your query already uses platformFeeAmount, so no change needed unless it references the client var)

if src == orig:
    raise SystemExit("[ABORT] No changes applied (already patched or patterns not found).")

p.write_text(src, encoding="utf-8")
print("[OK] Patched purchases.routes.ts to compute purchase escrow release fee server-side.")
PY

echo "✅ Done."
echo "Check fee usage:"
echo "  rg -n \"platformFeeAmountFromClient|computePlatformFeeSplit|platformFeeAmount\" src/routes/purchases.routes.ts"