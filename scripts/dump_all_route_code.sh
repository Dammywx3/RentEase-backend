#!/usr/bin/env bash
set -euo pipefail

OUT="routes_full_dump_$(date +%Y%m%d_%H%M%S).txt"
: > "$OUT"

echo "============================================================" | tee -a "$OUT"
echo "RentEase: FULL ROUTES DUMP (route declarations + context)" | tee -a "$OUT"
echo "Generated: $(date)" | tee -a "$OUT"
echo "PWD: $(pwd)" | tee -a "$OUT"
echo "============================================================" | tee -a "$OUT"
echo "" | tee -a "$OUT"

# List route files
FILES=$(ls -1 src/routes/*.ts 2>/dev/null || true)
if [ -z "${FILES}" ]; then
  echo "❌ No src/routes/*.ts files found" | tee -a "$OUT"
  exit 1
fi

echo "Route files:" | tee -a "$OUT"
echo "$FILES" | sed 's/^/ - /' | tee -a "$OUT"
echo "" | tee -a "$OUT"

# Helper: print header
print_file_header () {
  local f="$1"
  echo "============================================================" | tee -a "$OUT"
  echo "FILE: $f" | tee -a "$OUT"
  echo "------------------------------------------------------------" | tee -a "$OUT"
}

# 1) Dump ONLY route declaration lines (fast scan)
echo "================ ROUTE DECLARATION LINES ===================" | tee -a "$OUT"
for f in $FILES; do
  print_file_header "$f"
  rg -n --no-heading 'app\.(get|post|put|patch|delete)\(' "$f" \
    | tee -a "$OUT" || echo "  (no routes found)" | tee -a "$OUT"
  echo "" | tee -a "$OUT"
done

# 2) Dump CONTEXT around each route line (so we see full handler)
# We print 8 lines before and 80 lines after each route declaration.
echo "================ ROUTE HANDLER CONTEXT =====================" | tee -a "$OUT"
for f in $FILES; do
  # Get line numbers where route starts
  LINES=$(rg -n --no-heading 'app\.(get|post|put|patch|delete)\(' "$f" | cut -d: -f1 || true)
  if [ -z "${LINES}" ]; then
    continue
  fi

  print_file_header "$f"
  for ln in $LINES; do
    start=$((ln-8))
    [ $start -lt 1 ] && start=1
    end=$((ln+80))

    echo "" | tee -a "$OUT"
    echo "---- CONTEXT around line $ln (showing $start..$end) ----" | tee -a "$OUT"
    nl -ba "$f" | sed -n "${start},${end}p" | tee -a "$OUT"
  done
  echo "" | tee -a "$OUT"
done

# 3) Extra: show any broken quote patterns like app.post("
echo "================ BROKEN QUOTE CHECK ========================" | tee -a "$OUT"
rg -n --no-heading 'app\.(get|post|put|patch|delete)\("\s*$' src/routes \
  | tee -a "$OUT" || echo "✅ No obvious app.<verb>(\"<newline> broken quotes" | tee -a "$OUT"

echo "" | tee -a "$OUT"
echo "============================================================" | tee -a "$OUT"
echo "✅ Saved to: $OUT" | tee -a "$OUT"
echo "Now paste the terminal output OR run: cat $OUT" | tee -a "$OUT"
echo "============================================================" | tee -a "$OUT"
