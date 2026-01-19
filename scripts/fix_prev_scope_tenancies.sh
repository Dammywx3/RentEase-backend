#!/usr/bin/env bash
set -euo pipefail

FILE="src/repos/tenancies.repo.ts"

if [[ ! -f "$FILE" ]]; then
  echo "❌ File not found: $FILE"
  exit 1
fi

cp "$FILE" "$FILE.bak.$(date +%Y%m%d_%H%M%S)"
echo "✅ Backup created."

perl -0777 -i -pe '
  s/WHERE t\.id = \$1\s*\n\s*RETURNING\s*\n\s*\$\{TENANCY_SELECT\},/FROM prev\n      WHERE t.id = prev.id\n      RETURNING\n        ${TENANCY_SELECT_T},/g;
  s/WHERE t\.id = \$1\s*\n\s*RETURNING\s*\n\s*\$\{TENANCY_SELECT_T\},/FROM prev\n      WHERE t.id = prev.id\n      RETURNING\n        ${TENANCY_SELECT_T},/g;

  s/RETURNING\s*\n\s*\$\{TENANCY_SELECT\},/RETURNING\n        ${TENANCY_SELECT_T},/g;
' "$FILE"

echo "✅ Patched prev scope + RETURNING select list."
echo
echo "Next:"
echo "  1) Restart backend: npm run dev"
echo "  2) Re-run your PATCH start/end curl tests"
