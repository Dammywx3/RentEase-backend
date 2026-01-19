#!/usr/bin/env bash
set -euo pipefail

FILE="src/routes/webhooks.ts"
ts="$(date +%s)"

cp "$FILE" "$FILE.bak.$ts"
echo "Backup: $FILE.bak.$ts"

# Replace the whole resolveTransferWebhookContext function with a version that:
# - supports transfer_code / reference
# - supports reference="payout_<uuid>"
# - does NOT use deleted_at on payouts (payouts table has no deleted_at)
perl -0777 -i -pe '
  s{
    async\s+function\s+resolveTransferWebhookContext\s*\([^)]*\)\s*\{
    .*?
    \n\}
  }{
async function resolveTransferWebhookContext(client: any, event: any) {
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

  const found = await client.query<{
    organization_id: string;
  }>(
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
}gms
  } "$FILE";

echo "✅ Patched: $FILE"
echo
echo "---- quick verify ----"
rg -n "resolveTransferWebhookContext\\(" "$FILE" || true
rg -n "payout_" "$FILE" || true
rg -n "deleted_at" "$FILE" || echo "✅ No deleted_at refs in webhooks.ts"
echo
echo "---- typecheck ----"
npx tsc -p tsconfig.json --noEmit
echo "✅ tsc OK"
