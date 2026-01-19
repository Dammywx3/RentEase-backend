#!/usr/bin/env bash
set -euo pipefail

STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="scripts/_backup_rls_fix_${STAMP}"
mkdir -p "$BACKUP_DIR"

# The routes we know touch tx/RLS from your dump
FILES=(
  "src/routes/purchase_escrow.ts"
  "src/routes/purchase_close.ts"
  "src/routes/payments.ts"
  "src/routes/rent_invoices.ts"
  "src/routes/tenancies.ts"
  "src/routes/purchases.routes.ts"
  "src/routes/webhooks.ts"
  "src/routes/listings.ts"
  "src/routes/me.ts"
  "src/routes/organizations.ts"
  "src/routes/applications.ts"
  "src/routes/viewings.ts"
)

echo "============================================================"
echo "RentEase: RLS Fix Pass #1 (SAFE)"
echo "Backup dir: $BACKUP_DIR"
echo "============================================================"

# Backup
for f in "${FILES[@]}"; do
  if [[ -f "$f" ]]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$f")"
    cp "$f" "$BACKUP_DIR/$f"
  fi
done

echo "✅ Backed up route files."

# 1) Normalize any leftover import of withRlsTransaction from ../config/database.js -> ../db/rls_tx.js
for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || continue
  perl -0777 -i -pe '
    s/import\s*\{\s*withRlsTransaction\s*\}\s*from\s*"\.\.\/config\/database\.js";/import { withRlsTransaction } from "..\/db\/rls_tx.js";/g
  ' "$f"
done
echo "✅ Normalized withRlsTransaction imports (if any were old)."

# 2) Ensure UTC inside manual tx blocks (only if file has BEGIN and does NOT already set local time zone)
for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || continue

  if rg -n 'await\s+\w+\.query\("BEGIN"\);' "$f" >/dev/null 2>&1; then
    if ! rg -n 'SET LOCAL TIME ZONE' "$f" >/dev/null 2>&1; then
      # insert after the first BEGIN we see
      perl -0777 -i -pe '
        s/(await\s+\w+\.query\("BEGIN"\);\s*\n)/$1        await client.query("SET LOCAL TIME ZONE \x27UTC\x27");\n/s
      ' "$f"
      echo "✅ Added SET LOCAL TIME ZONE 'UTC' to: $f"
    else
      echo "ℹ️ UTC already present in: $f"
    fi
  fi
done

# 3) Generate a TODO report showing remaining manual pooling patterns we still need to refactor into withRlsTransaction
OUT="rls_fix_todo_${STAMP}.txt"
{
  echo "============================================================"
  echo "RLS TODO REPORT (after Fix Pass #1)"
  echo "Generated: $(date)"
  echo "============================================================"
  echo ""
  echo "A) Files still using app.pg.connect() (manual pool usage):"
  echo "------------------------------------------------------------"
  rg -n --no-heading 'app\.pg\.connect\(\)' src/routes || true
  echo ""
  echo "B) Files doing manual BEGIN/COMMIT/ROLLBACK:"
  echo "------------------------------------------------------------"
  rg -n --no-heading 'query\("BEGIN"\)|query\("COMMIT"\)|query\("ROLLBACK"\)' src/routes || true
  echo ""
  echo "C) Any direct set_config calls (should ideally be centralized in setPgContext):"
  echo "------------------------------------------------------------"
  rg -n --no-heading 'set_config\(' src | rg -v 'set_pg_context' || true
  echo ""
} > "$OUT"

echo "============================================================"
echo "✅ PASS #1 DONE"
echo "Backup: $BACKUP_DIR"
echo "TODO report: $OUT"
echo ""
echo "Next:"
echo "  npm run build"
echo "  cat $OUT"
echo "============================================================"
