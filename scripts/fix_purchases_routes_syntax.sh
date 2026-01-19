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
BACKUP="$FILE.bak.fix.$TS"
cp "$FILE" "$BACKUP"
echo "==> Backup: $BACKUP"

# 1) If file was accidentally duplicated, keep only the FIRST copy.
#    (Stop printing when we hit the 2nd header line.)
TMP1="$(mktemp)"
awk '
  BEGIN{c=0}
  /^\/\/ src\/routes\/purchases\.routes\.ts/ { c++; if (c==2) exit }
  { print }
' "$FILE" > "$TMP1"
mv "$TMP1" "$FILE"
echo "==> Dedupe pass done."

# 2) Prepare a clean /status block (correct braces/indentation).
STATUS_BLOCK="20 20 12 61 79 80 81 98 33 100 204 250 395 398 399 400 701cat <<'TSBLOCK'
  // ------------------------------------------------------------
  // POST /purchases/:purchaseId/status
  // body: { status: "<purchase_status>", note?: string }
  // ------------------------------------------------------------
  fastify.post<{
    Params: { purchaseId: string };
    Body: { status: string; note?: string };
  }>(
    "/purchases/:purchaseId/status",
    {
      preHandler: requireAuth,
      schema: {
        body: {
          type: "object",
          required: ["status"],
          additionalProperties: false,
          properties: {
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
            note: { type: "string", minLength: 1 },
          },
        },
      },
    },
    async (request, reply) => {
      const orgId = String(request.headers["x-organization-id"] || "");
      if (!orgId) {
        return reply.code(400).send({
          ok: false,
          error: "ORG_REQUIRED",
          message: "x-organization-id required",
        });
      }

      const actorUserId = (request as any).user?.userId ?? null;
      if (!actorUserId) {
        return reply
          .code(401)
          .send({ ok: false, error: "UNAUTHORIZED", message: "Missing auth user" });
      }

      const { purchaseId } = request.params;
      const newStatus = String(request.body.status || "");
      const note = request.body.note ?? null;

      const client = await fastify.pg.connect();
      try {
        // ✅ must be same connection (trigger actor + future RLS)
        await setPgContext(client, { userId: actorUserId, organizationId: orgId });

        const { rows } = await client.query(
          `
          update public.property_purchases
          set status = $3::purchase_status,
              updated_at = now()
          where id = $1::uuid
            and organization_id = $2::uuid
            and deleted_at is null
          returning
            id::text,
            organization_id::text,
            property_id::text,
            listing_id::text,
            buyer_id::text,
            seller_id::text,
            agreed_price::text,
            currency,
            status::text as status,
            payment_status::text as payment_status,
            paid_at::text as paid_at,
            refunded_at::text as refunded_at,
            created_at::text as created_at,
            updated_at::text as updated_at;
          `,
          [purchaseId, orgId, newStatus]
        );

        const row = rows[0];
        if (!row) {
          return reply
            .code(404)
            .send({ ok: false, error: "NOT_FOUND", message: "Purchase not found" });
        }

        return reply.send({ ok: true, data: { purchase: row, note } });
      } catch (err: any) {
        return reply.code(400).send({
          ok: false,
          error: err?.code || "STATUS_UPDATE_FAILED",
          message: err?.message || "Status update failed",
        });
      } finally {
        client.release();
      }
    }
  );

TSBLOCK

export STATUS_BLOCK

# 3) Replace an existing /status route block (if present), otherwise insert it before /refund.
perl -0777 -i -pe '
  my $blk = $ENV{STATUS_BLOCK};

  if ($m =~ /\/\/ POST \/purchases\/:purchaseId\/status/) {
    # Replace between status marker and refund marker
    $m =~ s{
      \n[ \t]*\/\/ ------------------------------------------------------------\n
      [ \t]*\/\/ POST \/purchases\/:purchaseId\/status[\s\S]*?
      (?=\n[ \t]*\/\/ ------------------------------------------------------------\n[ \t]*\/\/ POST \/purchases\/:purchaseId\/refund)
    }{\n$blk}msx;
  } else {
    # Insert before refund marker
    $m =~ s{
      (\n[ \t]*\/\/ ------------------------------------------------------------\n[ \t]*\/\/ POST \/purchases\/:purchaseId\/refund)
    }{\n$blk$1}msx;
  }
' "$FILE"

echo "✅ Fixed: $FILE"
echo "==> Sanity checks:"
echo " - occurrences of header:"
grep -n "^// src/routes/purchases.routes.ts" -n "$FILE" | wc -l | awk '{print "   header_count=" $1}'
echo " - status route present?"
grep -n "/purchases/:purchaseId/status" -n "$FILE" | head -n 3 || true
