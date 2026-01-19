# scripts/patch_fix_purchase_release_totals.sh
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$ROOT/.patch_backups/$TS"
mkdir -p "$BACKUP_DIR"

say() { printf "\n\033[1m%s\033[0m\n" "$*"; }
ok() { printf "✅ %s\n" "$*"; }
die() { printf "❌ %s\n" "$*"; exit 1; }

FILE="src/routes/purchases.routes.ts"
[[ -f "$FILE" ]] || die "Missing file: $FILE"

backup() {
  local dest="$BACKUP_DIR/${1//\//__}"
  cp -a "$1" "$dest"
  ok "Backup: $1 -> $dest"
}

say "Repo: $ROOT"
say "Backups: $BACKUP_DIR"
say "Patching: $FILE"

backup "$FILE"

python3 - "$FILE" <<'PY'
import re, sys, pathlib

path = pathlib.Path(sys.argv[1])
src = path.read_text(encoding="utf-8")
orig = src

# ------------------------------------------------------------
# Fix 1) Remove the accidental "newTotalHeld" lines inside escrow release route
# (These lines belong to HOLD route, not RELEASE.)
# ------------------------------------------------------------
bad_block = r"""
\s*const\s+currentHeld\s*=\s*Number\(\(purchase\s+as\s+any\)\?\.\s*escrow_held_amount\s*\?\?\s*0\);\s*
\s*newTotalHeld\s*=\s*currentHeld\s*\+\s*amount;\s*
"""
src, n1 = re.subn(bad_block, "\n", src, flags=re.VERBOSE)

# Also remove a stray 'newTotalHeld = ...' line if it exists alone (safety)
src, n1b = re.subn(r"^\s*newTotalHeld\s*=\s*.*?;\s*$\n", "", src, flags=re.MULTILINE)

# ------------------------------------------------------------
# Fix 2) Ensure release route has correct newTotalRelease logic
# (Only insert if missing.)
# ------------------------------------------------------------
if "const newTotalRelease" not in src:
    # Try to anchor right after we compute held/currentReleased
    anchor = r"(const\s+held\s*=\s*Number\(\s*purchase\.escrow_held_amount\s*\?\?\s*0\s*\);\s*\n\s*const\s+currentReleased\s*=\s*Number\(\s*\(purchase\s+as\s+any\)\.escrow_released_amount\s*\?\?\s*0\s*\);\s*)"
    m = re.search(anchor, src)
    if m:
        insert = m.group(1) + "\n        const newTotalRelease = currentReleased + amount;"
        src = src[:m.start(1)] + insert + src[m.end(1):]
    else:
        # Fallback: insert after first "const held =" in the file (conservative)
        src = re.sub(
            r"(const\s+held\s*=\s*Number\(\s*purchase\.escrow_held_amount\s*\?\?\s*0\s*\);\s*)",
            r"\1\n        const currentReleased = Number((purchase as any).escrow_released_amount ?? 0);\n        const newTotalRelease = currentReleased + amount;",
            src,
            count=1,
        )

# ------------------------------------------------------------
# Fix 3) Make sure we call purchase_escrow_release with NEW TOTAL RELEASE
# (If it's already correct, do nothing.)
# ------------------------------------------------------------
src = src.replace(
    "[purchaseId, orgId, amount, purchase.currency, platformFeeAmount, note ?? \"escrow release\"]",
    "[purchaseId, orgId, newTotalRelease, purchase.currency, platformFeeAmount, note ?? \"escrow release\"]"
)

# ------------------------------------------------------------
# IMPORTANT: Do NOT force platform fee anywhere in this patch.
# We keep platformFeeAmount coming from request body (or default 0).
# No fee percentages are hardcoded here.
# ------------------------------------------------------------

if src == orig:
    raise SystemExit("[ABORT] No changes applied (file already fixed or pattern changed).")

path.write_text(src, encoding="utf-8")
print("[OK] Patched:", path)
print(f"[INFO] Removed bad release-held lines: {n1 + n1b}")
PY

ok "Patch complete."

say "Quick sanity checks you can run:"
cat <<'EOF'
  rg -n "newTotalHeld" src/routes/purchases.routes.ts
  rg -n "newTotalRelease" src/routes/purchases.routes.ts
  rg -n "purchase_escrow_release" src/routes/purchases.routes.ts
EOF

ok "Done. Terminal will remain open."