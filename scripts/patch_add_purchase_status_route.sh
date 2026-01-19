#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

FILE="src/routes/purchases.routes.ts"
if [ ! -f "$FILE" ]; then
  echo "❌ File not found: $FILE"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP="$FILE.bak.$TS"
cp "$FILE" "$BACKUP"
echo "==> Backup: $BACKUP"

# If route already exists, do nothing
if grep -q '"/purchases/:purchaseId/status"' "$FILE"; then
  echo "ℹ️ /status route already present in $FILE (no changes)."
  exit 0
fi

# Insert the /status route right before the refund route comment
perl -0777 -i -pe 's@
(\s*)// ------------------------------------------------------------\n\1// POST /purchases/:purchaseId/refund@
$1// ------------------------------------------------------------\n\
$1// POST /purchases/:purchaseId/status\n\
$1// body: { status: \"<purchase_status>\", note?: string }\n\
$1// ------------------------------------------------------------\n\
$1fastify.post<{\n\
$1  Params: { purchaseId: string };\n\
$1  Body: { status: string; note?: string };\n\
$1}>(\n\
$1  \"/purchases/:purchaseId/status\",\n\
$1  {\n\
$1    preHandler: requireAuth,\n\
$1    schema: {\n\
$1      body: {\n\
$1        type: \"object\",\n\
$1        required: [\"status\"],\n\
$1        additionalProperties: false,\n\
$1        properties: {\n\
$1          status: {\n\
$1            type: \"string\",\n\
$1            minLength: 1,\n\
$1            enum: [\n\
$1              \"initiated\",\n\
$1              \"offer_made\",\n\
$1              \"offer_accepted\",\n\
$1              \"under_contract\",\n\
$1              \"paid\",\n\
$1              \"escrow_opened\",\n\
$1              \"deposit_paid\",\n\
$1              \"inspection\",\n\
$1              \"financing\",\n\
$1              \"appraisal\",\n\
$1              \"title_search\",\n\
$1              \"closing_scheduled\",\n\
$1              \"closed\",\n\
$1              \"cancelled\",\n\
$1              \"refunded\"\n\
$1            ],\n\
$1          },\n\
$1          note: { type: \"string\", minLength: 1 },\n\
$1        },\n\
$1      },\n\
$1    },\n\
$1  },\n\
$1  async (request, reply) => {\n\
$1    const orgId = String(request.headers[\"x-organization-id\"] || \"\");\n\
$1    if (!orgId) {\n\
$1      return reply.code(400).send({\n\
$1        ok: false,\n\
$1        error: \"ORG_REQUIRED\",\n\
$1        message: \"x-organization-id required\",\n\
$1      });\n\
$1    }\n\
\n\
$1    const actorUserId = (request as any).user?.userId ?? null;\n\
$1    if (!actorUserId) {\n\
$1      return reply\n\
$1        .code(401)\n\
$1        .send({ ok: false, error: \"UNAUTHORIZED\", message: \"Missing auth user\" });\n\
$1    }\n\
\n\
$1    const { purchaseId } = request.params;\n\
$1    const newStatus = String((request.body as any)?.status || \"\");\n\
$1    const note = (request.body as any)?.note ?? null;\n\
\n\
$1    const client = await fastify.pg.connect();\n\
$1    try {\n\
$1      // ✅ must be same connection (trigger actor + future RLS)\n\
$1      await setPgContext(client, { userId: actorUserId, organizationId: orgId });\n\
\n\
$1      const { rows } = await client.query(\n\
$1        `\n\
$1        update public.property_purchases\n\
$1        set status = $3::purchase_status,\n\
$1            updated_at = now()\n\
$1        where id = $1::uuid\n\
$1          and organization_id = $2::uuid\n\
$1          and deleted_at is null\n\
$1        returning\n\
$1          id::text,\n\
$1          organization_id::text,\n\
$1          property_id::text,\n\
$1          listing_id::text,\n\
$1          buyer_id::text,\n\
$1          seller_id::text,\n\
$1          agreed_price::text,\n\
$1          currency,\n\
$1          status::text as status,\n\
$1          payment_status::text as payment_status,\n\
$1          paid_at::text as paid_at,\n\
$1          refunded_at::text as refunded_at,\n\
$1          created_at::text as created_at,\n\
$1          updated_at::text as updated_at;\n\
$1        `,\n\
$1        [purchaseId, orgId, newStatus]\n\
$1      );\n\
\n\
$1      const row = rows[0];\n\
$1      if (!row) {\n\
$1        return reply\n\
$1          .code(404)\n\
$1          .send({ ok: false, error: \"NOT_FOUND\", message: \"Purchase not found\" });\n\
$1      }\n\
\n\
$1      return reply.send({ ok: true, data: { purchase: row, note } });\n\
$1    } catch (err: any) {\n\
$1      return reply.code(400).send({\n\
$1        ok: false,\n\
$1        error: err?.code || \"STATUS_UPDATE_FAILED\",\n\
$1        message: err?.message || \"Status update failed\",\n\
$1      });\n\
$1    } finally {\n\
$1      client.release();\n\
$1    }\n\
$1  }\n\
$1);\n\
\n\
$1// ------------------------------------------------------------\n\
$1// POST /purchases/:purchaseId/refund@
@gms' "$FILE"

echo "✅ Inserted /status route into: $FILE"
echo "==> Verify (show route headers):"
grep -n "/purchases/:purchaseId/status" -n "$FILE" || true
