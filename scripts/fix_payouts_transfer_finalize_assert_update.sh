#!/usr/bin/env bash
set -euo pipefail

FILE="src/services/payouts.service.ts"
ts="$(date +%s)"
cp "$FILE" "$FILE.bak.$ts"
echo "Backup: $FILE.bak.$ts"

# Replace: await client.query(`update payouts ...`, [...]);
# With: const upd = await client.query(...); if rowCount!=1 => return error
perl -0777 -i -pe '
  s/await\s+client\.query\(\s*`(\s*update\s+public\.payouts[\s\S]*?where\s+id\s*=\s*\$1::uuid;[\s\S]*?)`\s*,\s*\[([^\]]*?)\]\s*\);\s*/
const upd = await client.query(
    `$1`,
    [$2]
  );

  if ((upd as any)?.rowCount !== 1) {
    return { ok: false, error: "PAYOUT_UPDATE_ZERO", message: "Update did not affect 1 row (RLS or missing payout)" };
  }

  /s;
' "$FILE"

echo "✅ Patched: $FILE"
echo
echo "---- typecheck ----"
npx tsc -p tsconfig.json --noEmit
echo "✅ tsc OK"
