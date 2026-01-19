#!/usr/bin/env bash
set -euo pipefail

FILE="src/routes/purchase_close.ts"

if [ ! -f "$FILE" ]; then
  echo "❌ $FILE not found. Paste your close purchase route file path."
  exit 1
fi

cp "$FILE" "$FILE.bak.$(date +%s)"
echo "✅ Backup: $FILE.bak.*"

# Patch: ensure actorId is derived and passed to purchase_close_complete(...)
# We do a safe, minimal approach:
# - Add actorId extraction near orgId extraction
# - Replace any SQL call that uses purchase_close_complete($1,$2,...) with a 4-arg call
#   and add actorId + note binding.

perl -0777 -i -pe '
  # 1) Add actorId extraction if not present
  if ($_ !~ /const\s+actorId\s*=/) {
    $_ =~ s/(const\s+orgId\s*=\s*[^;]+;\s*)/$1\n  const actorId = String((request as any).user?.id || (request as any).userId || (request as any).user?.userId || (request as any).user?.sub || "").trim();\n/;
  }

  # 2) If the function call is a 2-arg or 3-arg call, force 4 args.
  # Common patterns we’ve seen in your codebase:
  #   select public.purchase_close_complete($1::uuid, $2::uuid, $3::uuid, $4::text) as result
  # Or missing $3/$4. We standardize to 4 args.
  $_ =~ s/public\.purchase_close_complete\s*\(\s*\$1::uuid\s*,\s*\$2::uuid\s*\)/public.purchase_close_complete(\$1::uuid, \$2::uuid, \$3::uuid, \$4::text)/g;

  # 3) Ensure query params include actorId + note.
  # Look for: [purchaseId, orgId] or [purchaseId, orgId, note] and expand.
  $_ =~ s/\[\s*purchaseId\s*,\s*orgId\s*\]/[purchaseId, orgId, actorId || null, (body as any)?.note || null]/g;
  $_ =~ s/\[\s*purchaseId\s*,\s*orgId\s*,\s*note\s*\]/[purchaseId, orgId, actorId || null, note || null]/g;

  # 4) If note var not defined, add a simple note parse from body
  if ($_ !~ /const\s+note\s*=/) {
    $_ =~ s/(const\s+purchaseId\s*=\s*[^;]+;\s*)/$1\n  const body = (request as any).body || {};\n  const note = typeof body.note === "string" ? body.note : null;\n/;
  }

  $_;
' "$FILE"

echo "✅ Patched $FILE"
echo
echo "==> Preview relevant lines:"
grep -n "actorId" -n "$FILE" || true
grep -n "purchase_close_complete" -n "$FILE" || true

echo
echo "NEXT:"
echo "1) Restart server"
echo "2) Re-run close (use a NEW purchase if your existing one is already closed):"
echo "   export DEV_EMAIL='dev_...@rentease.local'"
echo "   export DEV_PASS='Passw0rd!234'"
echo "   ./scripts/e2e_close_purchase.sh <PURCHASE_ID>"
echo
echo "3) Verify audit changed_by:"
echo "   DB=rentease psql -X -P pager=off -d \"$DB\" -c \"select table_name, record_id::text, operation::text, changed_by::text, created_at from public.audit_logs where table_name='purchase' order by created_at desc limit 5;\""
