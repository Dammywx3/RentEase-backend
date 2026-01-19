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

# -----------------------------
# A) FIX HOLD ROUTE newTotalHeld
# Ensure after fetching purchase we compute:
#   const currentHeld = Number(purchase.escrow_held_amount ?? 0);
#   newTotalHeld = currentHeld + amount;
# -----------------------------

# Find the hold route fetch line and ensure the calc exists after it
hold_fetch_pat = r"(const purchase = await fetchPurchaseOr404\(client,\s*purchaseId,\s*orgId\);\s*)"
m = re.search(hold_fetch_pat, src)
if m:
    hold_block_start = m.end()
    # Look ahead a bit to see if newTotalHeld is assigned already
    window = src[hold_block_start:hold_block_start+800]
    if "newTotalHeld =" not in window:
        inject = (
            "const currentHeld = Number((purchase as any)?.escrow_held_amount ?? 0);\n"
            "        newTotalHeld = currentHeld + amount;\n"
        )
        src = src[:hold_block_start] + inject + src[hold_block_start:]

# Also fix the situation where the purchase null-check happens after using purchase
# Ensure we check purchase immediately after fetch (if not already)
# If we see "const purchase = ..." and later "if (!purchase)" but after other lines,
# we won't try to aggressively reorder (risky), but at least we now compute after fetch.
# Your code already checks if (!purchase) soon after, which is okay.

# -----------------------------
# B) FIX STATUS ROUTE platformFeeAmount undefined
# In autoEscrow close block, before calling purchase_escrow_release, define platformFeeAmount
# based on RELEASE DELTA = held - alreadyReleased (the amount that is newly being released).
# -----------------------------

# We detect the exact auto-release call that currently uses "platformFeeAmount" undeclared.
auto_release_call_pat = r"\[purchaseId,\s*orgId,\s*held,\s*refreshed\.currency,\s*platformFeeAmount,\s*note \?\? \"auto escrow release\"\]"
if re.search(auto_release_call_pat, src):
    # Insert computation right before the await client.query(`select public.purchase_escrow_release...` in that block.
    # We'll inject after: "if (held > alreadyReleased) {"
    marker = "if (held > alreadyReleased) {"
    if marker in src and "const platformFeeAmount =" not in src[src.find(marker):src.find(marker)+1200]:
        inject = """
                // ✅ Server-side platform fee (do NOT trust client)
                // For auto-release we are releasing the remaining DELTA:
                const releaseDelta = Math.max(0, held - alreadyReleased);
                const split = computePlatformFeeSplit({
                  paymentKind: "buy",
                  amount: releaseDelta,
                  currency: refreshed.currency,
                });
                const platformFeeAmount = Number(split.platformFee ?? 0);

"""
        src = src.replace(marker, marker + inject, 1)

# If the file has platformFeeAmountFromClient but never used, keep it (harmless).
# But we should also stop using platformFeeAmountFromClient in status route if it exists.
# We'll ensure the client value is not mistakenly used; and silence unused variable warning.
status_client_fee_pat = r"const platformFeeAmountFromClient = Number\(request\.body\.platformFeeAmount \?\? 0\);\s*"
if re.search(status_client_fee_pat, src):
    # ensure "void platformFeeAmountFromClient;" exists in status route after declaration
    # We'll add it right after the declaration if not present soon after.
    decl_match = re.search(status_client_fee_pat, src)
    if decl_match:
        end = decl_match.end()
        window = src[end:end+200]
        if "void platformFeeAmountFromClient" not in window:
            src = src[:end] + "\n      void platformFeeAmountFromClient;\n" + src[end:]

# -----------------------------
# Done
# -----------------------------
if src == orig:
    raise SystemExit("[ABORT] No changes applied (already fixed or patterns not found).")

p.write_text(src, encoding="utf-8")
print("[OK] Patched purchases.routes.ts (hold newTotalHeld + status platformFeeAmount).")
PY

echo "✅ Done."

echo
echo "Sanity checks:"
echo "  rg -n \"newTotalHeld =\" $FILE"
echo "  rg -n \"const platformFeeAmount =\" $FILE"
echo "  rg -n \"platformFeeAmount, note \\?\\? \\\"auto escrow release\\\"\" $FILE"