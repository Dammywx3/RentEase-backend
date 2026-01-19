#!/usr/bin/env bash
set -euo pipefail

STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="scripts/_backup_fix_broken_routes_${STAMP}"
mkdir -p "$BACKUP_DIR"

echo "============================================================"
echo "Fix broken route tokens: \$1\$2 -> app.<verb>(\""
echo "Backup: $BACKUP_DIR"
echo "============================================================"

FILES="$(rg -l '\$1\$2' src/routes || true)"

if [[ -z "${FILES}" ]]; then
  echo "✅ No \$1\$2 corruption found in src/routes"
  exit 0
fi

echo "Found corrupted files:"
echo "$FILES" | sed 's/^/ - /'
echo ""

while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  cp -a "$f" "$BACKUP_DIR/"

  tmp="${f}.tmp.${STAMP}"

  awk '
  BEGIN { verb="" }
  {
    # Infer verb from nearby comments
    if ($0 ~ /\/\/[[:space:]]*GET\b/) verb="get";
    else if ($0 ~ /\/\/[[:space:]]*POST\b/) verb="post";
    else if ($0 ~ /\/\/[[:space:]]*PUT\b/) verb="put";
    else if ($0 ~ /\/\/[[:space:]]*PATCH\b/) verb="patch";
    else if ($0 ~ /\/\/[[:space:]]*DELETE\b/) verb="delete";

    if ($0 ~ /\$1\$2/) {
      if (verb == "") verb="get"; # fallback
      gsub(/\$1\$2/, "app." verb "(\"", $0);
    }

    print $0
  }' "$f" > "$tmp"

  mv "$tmp" "$f"
  echo "✅ fixed: $f"
done <<< "$FILES"

echo ""
echo "Re-scan (should be empty):"
rg -n '\$1\$2' src/routes || true

echo "============================================================"
echo "✅ DONE"
echo "Next:"
echo "  npm run build"
echo "  # restart dev server (Ctrl+C then npm run dev)"
echo "============================================================"
