#!/usr/bin/env bash
set -euo pipefail

FILE="src/routes/webhooks.ts"
ts="$(date +%s)"

cp "$FILE" "$FILE.bak.$ts"
echo "Backup: $FILE.bak.$ts"

# 1) Switch call sites to V2 (safe: only changes function name)
perl -0777 -i -pe 's/\bresolveTransferWebhookContext\s*\(/resolveTransferWebhookContextV2(/g' "$FILE"

# 2) Append V2 helper if not already present
if ! rg -n "function resolveTransferWebhookContextV2" "$FILE" >/dev/null 2>&1; then
  cat >> "$FILE" <<'TS'

// ---------------------------------------------------------------------
// V2: transfer webhook context resolver (supports reference="payout_<uuid>")
// ---------------------------------------------------------------------
async function resolveTransferWebhookContextV2(client: any, event: any) {
  const asText = (v: any) => (v == null ? "" : String(v)).trim();

  const ref = asText(event?.data?.reference);
  const transferCode = asText(event?.data?.transfer_code);
  const paystackId = asText(event?.data?.id);

  // If reference is "payout_<uuid>", extract payoutId
  let payoutIdFromRef: string | null = null;
  if (ref && ref.toLowerCase().startsWith("payout_")) {
    const maybe = ref.slice("payout_".length).trim();
    if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(maybe)) {
      payoutIdFromRef = maybe;
    }
  }

  // NOTE: payouts table has NO deleted_at
  const found = await client.query<{ organization_id: string }>(
    `
    select p.organization_id::text as organization_id
    from public.payouts p
    where
      ($1 <> '' and p.gateway_payout_id = $1)
      or ($2 <> '' and p.gateway_payout_id = $2)
      or ($3 is not null and p.id = $3::uuid)
    limit 1;
    `,
    [transferCode, ref, payoutIdFromRef]
  );

  const row = found.rows[0];
  if (!row?.organization_id) return null;

  return {
    organizationId: row.organization_id,
    reference: ref || transferCode || paystackId || "transfer",
  };
}
TS
fi

echo "✅ Patched: $FILE"
echo
echo "---- verify ----"
rg -n "resolveTransferWebhookContextV2\\(" "$FILE" || true
rg -n "payout_" "$FILE" || true

echo
echo "---- typecheck ----"
npx tsc -p tsconfig.json --noEmit
echo "✅ tsc OK"
