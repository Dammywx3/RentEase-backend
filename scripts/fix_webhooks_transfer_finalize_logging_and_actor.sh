#!/usr/bin/env bash
set -euo pipefail

FILE="src/routes/webhooks.ts"
ts="$(date +%s)"

cp "$FILE" "$FILE.bak.$ts"
echo "Backup: $FILE.bak.$ts"

# 1) Ensure systemActor is derived from WEBHOOK_ACTOR_USER_ID (and trimmed)
# Covers cases where old code used SYSTEM_ACTOR_USER_ID or something else.
perl -0777 -i -pe '
  # Replace common patterns that define systemActor
  s/const\s+systemActor\s*=\s*[^;]+;/const systemActor = String(process.env.WEBHOOK_ACTOR_USER_ID || process.env.SYSTEM_ACTOR_USER_ID || \"\").trim();/s
  unless $_ =~ /WEBHOOK_ACTOR_USER_ID/;

  # If systemActor still not defined anywhere, insert it near top of handler block.
  if ($_ !~ /const systemActor = String\(process\.env\.WEBHOOK_ACTOR_USER_ID/) {
    s/(app\.post\([^\n]*\/webhooks\/paystack[^\n]*\n[^\{]*\{\s*\n)/$1  const systemActor = String(process.env.WEBHOOK_ACTOR_USER_ID || process.env.SYSTEM_ACTOR_USER_ID || \"\").trim();\n/s;
  }
' "$FILE"

# 2) Make transfer finalize call always pass actorUserId: systemActor
perl -0777 -i -pe '
  s/const\s+res\s*=\s*await\s+finalizePaystackTransferEvent\(\s*pg\s*,\s*\{\s*([^}]*)\s*\}\s*\)\s*;/do {\n          const res = await finalizePaystackTransferEvent(pg, { $1 });\n          if (!systemActor) {\n            app.log.warn({ reference: ctx?.reference, orgId: ctx?.organizationId }, \"WEBHOOK_ACTOR_USER_ID missing - transfer finalize may be blocked by RLS\");\n          }\n          if (!res.ok) {\n            app.log.warn({ error: res.error, message: res.message, reference: ctx.reference, orgId: ctx.organizationId }, \"paystack transfer finalize failed\");\n          } else {\n            app.log.info({ reference: ctx.reference, orgId: ctx.organizationId }, \"paystack transfer finalize ok\");\n          }\n        } while (0);/sms
  if $_ =~ /finalizePaystackTransferEvent\(\s*pg\s*,/s;

  # Ensure actorUserId is present inside the call args (best-effort add if missing)
  s/(finalizePaystackTransferEvent\(\s*pg\s*,\s*\{\s*)(?![^}]*actorUserId)/$1actorUserId: systemActor,\n            /sms;
' "$FILE"

echo "✅ Patched: $FILE"
echo
echo "---- verify key lines ----"
rg -n "WEBHOOK_ACTOR_USER_ID|finalizePaystackTransferEvent\\(pg|actorUserId: systemActor|transfer finalize ok|transfer finalize failed" "$FILE" || true

echo
echo "---- typecheck ----"
npx tsc -p tsconfig.json --noEmit
echo "✅ tsc OK"
