#!/usr/bin/env bash
set -euo pipefail

STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="scripts/_backup_fix_route_verbs_${STAMP}"
mkdir -p "$BACKUP_DIR"

echo "============================================================"
echo "Fix route verbs based on preceding // GET/POST/PUT/PATCH/DELETE comments"
echo "Backup: $BACKUP_DIR"
echo "============================================================"

FILES="$(ls -1 src/routes/*.ts 2>/dev/null || true)"
if [[ -z "$FILES" ]]; then
  echo "No route files found."
  exit 0
fi

for f in $FILES; do
  cp -a "$f" "$BACKUP_DIR/"

  perl -0777 -i -pe '
    s/(\/\/\s*POST[^\n]*\n\s*)app\.get\(/$1app.post(/g;
    s/(\/\/\s*PUT[^\n]*\n\s*)app\.get\(/$1app.put(/g;
    s/(\/\/\s*PATCH[^\n]*\n\s*)app\.get\(/$1app.patch(/g;
    s/(\/\/\s*DELETE[^\n]*\n\s*)app\.get\(/$1app.delete(/g;
  ' "$f"
done

echo "✅ patched route verbs (see backup if you want to diff)"
echo ""
echo "Now check for duplicated same-method same-path quickly (best-effort):"
echo "  rg -n \"app\\.(get|post|put|patch|delete)\\(\\\"/:id\\\"\" src/routes | sort"
echo "============================================================"
