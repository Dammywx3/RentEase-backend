#!/usr/bin/env bash
set -euo pipefail

echo "=== Fix: remove payouts.deleted_at filters (payouts table has no deleted_at) ==="
echo "PWD: $(pwd)"

FILES="src/routes/webhooks.ts src/services/payouts.service.ts"
ts="$(date +%s)"

for f in $FILES; do
  if [ ! -f "$f" ]; then
    echo "❌ Missing file: $f"
    exit 1
  fi

  cp "$f" "$f.bak.$ts"
  echo "Backup: $f.bak.$ts"

  # Remove ANY "... AND <alias>.deleted_at IS NULL" lines/segments
  # Remove ANY "... AND deleted_at IS NULL" lines/segments (these files are payout-related)
  perl -0777 -i -pe '
    s/\n[ \t]*and[ \t]+[a-zA-Z_][a-zA-Z0-9_]*\.deleted_at[ \t]+is[ \t]+null[ \t]*//ig;
    s/[ \t]+and[ \t]+[a-zA-Z_][a-zA-Z0-9_]*\.deleted_at[ \t]+is[ \t]+null\b//ig;

    s/\n[ \t]*and[ \t]+deleted_at[ \t]+is[ \t]+null[ \t]*//ig;
    s/[ \t]+and[ \t]+deleted_at[ \t]+is[ \t]+null\b//ig;
  ' "$f"

  echo "✅ Patched: $f"
done

echo
echo "---- verify remaining deleted_at refs in these files ----"
rg -n "deleted_at" src/routes/webhooks.ts src/services/payouts.service.ts || echo "✅ No deleted_at refs remain in those files."

echo
echo "---- typecheck ----"
npx tsc -p tsconfig.json --noEmit
echo "✅ tsc OK"
