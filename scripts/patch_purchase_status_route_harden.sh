#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

FILE="src/routes/purchases.routes.ts"

if [ ! -f "$FILE" ]; then
  echo "❌ File not found: $FILE"
  exit 1
fi

# Ensure scripts dir exists
mkdir -p scripts

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP="$FILE.bak.$TS"
cp "$FILE" "$BACKUP"
echo "==> Backup created: $BACKUP"

# 1) Ensure setPgContext import exists (you already have it, but keep safe)
#    If missing, insert after Fastify import line.
if ! grep -q 'setPgContext' "$FILE"; then
  perl -i -pe 'if($.==1){s@^@// src/routes/purchases.routes.ts\n@} ' "$FILE"
  perl -0777 -i -pe '
    s@import\s+type\s+\{\s*FastifyInstance\s*\}\s+from\s+"fastify";@
import type { FastifyInstance } from "fastify";
import { setPgContext } from "../db/set_pg_context.js";@s
  ' "$FILE"
fi

# 2) Replace the manual set_config block in /status route with setPgContext
#    Your current code does:
#      const client = await fastify.pg.connect();
#      await client.query(set_config user)
#      await client.query(set_config org)
#      try { ... }
#
#    We want:
#      const client = await fastify.pg.connect();
#      try { await setPgContext(client,...); ... }
perl -0777 -i -pe '
  s@
    const\s+client\s*=\s*await\s+fastify\.pg\.connect\(\);\s*
    \s*#?\s*//\s*IMPORTANT:.*?\n
    \s*await\s+client\.query\("select\s+set_config\(\x27app\.user_id\x27,\s*\$1,\s*true\)"[^\n]*\);\s*\n
    \s*await\s+client\.query\("select\s+set_config\(\x27app\.organization_id\x27,\s*\$1,\s*true\)"[^\n]*\);\s*\n
    \s*try\s*\{
  @
    const client = await fastify.pg.connect();

    try {
      // ✅ must be same connection (RLS + trigger actor + future RLS)
      await setPgContext(client, { userId: actorUserId, organizationId: orgId });
  @gsx
' "$FILE"

# 3) Harden schema enum for /status route
# Replace: status: { type: "string" }
# with enum list that matches purchase_status values.
perl -0777 -i -pe '
  s@
    status:\s*\{\s*type:\s*"string"\s*\},
  @
    status: {
      type: "string",
      minLength: 1,
      enum: [
        "initiated",
        "offer_made",
        "offer_accepted",
        "under_contract",
        "paid",
        "escrow_opened",
        "deposit_paid",
        "inspection",
        "financing",
        "appraisal",
        "title_search",
        "closing_scheduled",
        "closed",
        "cancelled",
        "refunded"
      ],
    },
  @gsx
' "$FILE"

# 4) Optional: note minLength if present as { type: "string" }
perl -0777 -i -pe '
  s@
    note:\s*\{\s*type:\s*"string"\s*\},
  @
    note: { type: "string", minLength: 1 },
  @gsx
' "$FILE"

echo "✅ Patched: $FILE"

echo "==> Quick verify: show the /status route header + first few lines after it"
grep -n "/purchases/:purchaseId/status" -n "$FILE" | head -n 3 || true

echo
echo "✅ Done."
