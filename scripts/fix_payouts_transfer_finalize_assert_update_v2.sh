#!/usr/bin/env bash
set -euo pipefail

FILE="src/services/payouts.service.ts"
ts="$(date +%s)"
cp "$FILE" "$FILE.bak.$ts"
echo "Backup: $FILE.bak.$ts"

# 1) Remove any previously-inserted dangling upd check blocks (best-effort)
perl -0777 -i -pe '
  s/\n\s*if\s*\(\s*\(upd\s+as\s+any\)\?\.\s*rowCount\s*!==\s*1\s*\)\s*\{\s*\n\s*return\s*\{\s*ok:\s*false,\s*error:\s*"PAYOUT_UPDATE_ZERO"[\s\S]*?\n\s*\}\s*\n//s;
' "$FILE"

# 2) Replace the payout UPDATE call in finalizePaystackTransferEvent with:
#    const upd = await client.query(...); if rowCount !== 1 => return error
perl -0777 -i -pe '
  s/await\s+client\.query\(\s*`
(\s*update\s+public\.payouts[\s\S]*?where\s+id\s*=\s*\$1::uuid;[\s\S]*?)
`\s*,\s*\[([^\]]*?)\]\s*\);\s*/const upd = await client.query(
    `$1`,
    [$2]
  );

  if ((upd as any)?.rowCount !== 1) {
    return { ok: false, error: "PAYOUT_UPDATE_ZERO", message: "Update affected 0 rows (RLS or payout mismatch)" };
  }

  /sm;
' "$FILE"

echo "✅ Patched: $FILE"
echo
echo "---- typecheck ----"
npx tsc -p tsconfig.json --noEmit
echo "✅ tsc OK"
