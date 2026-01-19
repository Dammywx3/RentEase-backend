#!/usr/bin/env bash
set -euo pipefail

FILE="src/routes/webhooks.ts"
if [[ ! -f "$FILE" ]]; then
  echo "ERROR: not found: $FILE"
  exit 1
fi

ts=$(date +%s)
cp "$FILE" "${FILE}.bak.${ts}"
echo "Backup: ${FILE}.bak.${ts}"

# Add actorUserId: systemActor into finalizePaystackTransferEvent call
perl -0777 -i -pe '
  s/const res = await finalizePaystackTransferEvent\(pg,\s*\{\s*\n\s*organizationId:\s*ctx\.organizationId,\s*\n\s*event,\s*\n\s*\}\s*\);/const res = await finalizePaystackTransferEvent(pg, {\n            organizationId: ctx.organizationId,\n            actorUserId: systemActor,\n            event,\n          });/s
' "$FILE"

echo "✅ Patched: $FILE"
echo "---- verify ----"
rg -n "finalizePaystackTransferEvent\\(pg, \\{|actorUserId: systemActor" "$FILE" || true
