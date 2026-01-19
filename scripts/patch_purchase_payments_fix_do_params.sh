#!/usr/bin/env bash
set -euo pipefail

FILE="src/services/purchase_payments.service.ts"
if [ ! -f "$FILE" ]; then
  echo "❌ Not found: $FILE"
  exit 1
fi

mkdir -p scripts/.bak
ts="$(date +%Y%m%d_%H%M%S)"
cp "$FILE" "scripts/.bak/purchase_payments.service.ts.bak.$ts"
echo "✅ backup -> scripts/.bak/purchase_payments.service.ts.bak.$ts"

# Replace the DO $$ ... $$ block that incorrectly uses $1/$2 with safe SQL
perl -0777 -i -pe 's@
\s*//\s*3\)\s*Try\s*to\s*set\s*status=.*?\n\s*await\s+client\.query\(\s*`.*?DO\s+\$\$.*?\$\$;\s*`,\s*\[\s*purchase\.id\s*,\s*args\.organizationId\s*\]\s*\);\s*
@
  // 3) Optionally advance purchase status (SAFE).
  // IMPORTANT: Do not use $1/$2 inside DO $$ ... $$ because they are NOT SQL bind params.
  const canSetPaid = await client.query<{ ok: boolean }>(
    `
    SELECT EXISTS (
      SELECT 1
      FROM pg_type t
      JOIN pg_enum e ON t.oid = e.enumtypid
      WHERE t.typname = '\''purchase_status'\''
        AND e.enumlabel = '\''paid'\''
    ) AS ok;
    `
  );

  if (canSetPaid.rows?.[0]?.ok) {
    await client.query(
      `
      UPDATE public.property_purchases
      SET status = '\''paid'\''::purchase_status,
          updated_at = NOW()
      WHERE id = $1::uuid
        AND organization_id = $2::uuid
        AND deleted_at IS NULL;
      `,
      [purchase.id, args.organizationId]
    );
  }

@sg' "$FILE"

echo "✅ PATCHED: $FILE"
echo "➡️ Restart server after this: npm run dev"
