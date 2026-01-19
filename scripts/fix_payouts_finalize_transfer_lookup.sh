#!/usr/bin/env bash
set -euo pipefail

FILE="src/services/payouts.service.ts"
if [[ ! -f "$FILE" ]]; then
  echo "ERROR: not found: $FILE"
  exit 1
fi

ts=$(date +%s)
bak="${FILE}.bak.${ts}"
cp "$FILE" "$bak"
echo "Backup: $bak"

# Replace the entire exported finalizePaystackTransferEvent(...) function with a fixed one.
FILE_HINT="" perl -0777 -i -pe '
  my $re = qr{
    export\s+async\s+function\s+finalizePaystackTransferEvent
    \s*\([^)]*\)\s*:\s*Promise<[^>]*>\s*\{
    .*?
    \n\}
  }sx;

  my $replacement = q{
export async function finalizePaystackTransferEvent(
  client: PoolClient,
  args: {
    event: any;
    actorUserId?: string | null;
    organizationId?: string | null; // optional; we will derive from payout row if missing
  }
): Promise<{ ok: true } | { ok: false; error: string; message?: string }> {
  const asText = (v: any) => (v == null ? "" : String(v)).trim();

  const evName = asText(args?.event?.event);
  if (evName !== "transfer.success" && evName !== "transfer.failed" && evName !== "transfer.reversed") {
    return { ok: true };
  }

  const ref = asText(args?.event?.data?.reference);
  const transferCode = asText(args?.event?.data?.transfer_code);
  const paystackId = asText(args?.event?.data?.id);

  // Prefer transfer_code, else reference, else id
  const gatewayKey = transferCode || ref || paystackId;

  // If reference is "payout_<uuid>", extract payoutId
  let payoutIdFromRef: string | null = null;
  if (ref.toLowerCase().startsWith("payout_")) {
    const maybe = ref.slice("payout_".length).trim();
    // basic uuid format check (avoid throwing)
    if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(maybe)) {
      payoutIdFromRef = maybe;
    }
  }

  // Find payout by:
  // 1) gateway_payout_id == transfer_code
  // 2) gateway_payout_id == reference
  // 3) id == extracted uuid from reference payout_<uuid>
  const found = await client.query<{
    id: string;
    organization_id: string;
    status: string | null;
  }>(
    `
    select
      p.id::text as id,
      p.organization_id::text as organization_id,
      p.status::text as status
    from public.payouts p
    where
      ($1 <> "" and p.gateway_payout_id = $1)
      or ($2 <> "" and p.gateway_payout_id = $2)
      or ($3 is not null and p.id = $3::uuid)
    limit 1
    for update;
    `,
    [transferCode, ref, payoutIdFromRef]
  );

  const payout = found.rows[0];
  if (!payout) {
    return {
      ok: false,
      error: "PAYOUT_NOT_FOUND",
      message: `transfer_code=${transferCode || "-"} reference=${ref || "-"} payoutIdFromRef=${payoutIdFromRef || "-"}`,
    };
  }

  // Must be a real admin user UUID for is_admin() to pass (or rentease_service)
  const actor = asText(args.actorUserId || process.env.WEBHOOK_ACTOR_USER_ID || "");
  if (!actor) return { ok: false, error: "WEBHOOK_ACTOR_USER_ID_MISSING" };

  // Ensure admin context + correct org before UPDATE (RLS + triggers)
  await setPgContext(client, {
    organizationId: payout.organization_id,
    userId: actor,
    role: "admin",
    eventNote: `paystack:${evName}`,
  });

  const nextStatus =
    evName === "transfer.success"
      ? "successful"
      : evName === "transfer.reversed"
      ? "reversed"
      : "failed";

  await client.query(
    `
    update public.payouts
    set
      status = $2::public.payout_status,
      processed_at = coalesce(processed_at, now()),
      gateway_payout_id = coalesce(gateway_payout_id, $3::text),
      gateway_response = coalesce(gateway_response, '{}'::jsonb) || $4::jsonb,
      updated_at = now()
    where id = $1::uuid;
    `,
    [payout.id, nextStatus, gatewayKey || null, JSON.stringify(args.event)]
  );

  return { ok: true };
}
  };

  if ($_ !~ $re) {
    die "Patch failed: could not locate finalizePaystackTransferEvent() export in $ENV{FILE_HINT}\n";
  }
  $_ =~ s/$re/$replacement/s;
' "$FILE"
echo "✅ Patched: $FILE"
echo
echo "---- verify function exists ----"
rg -n "export async function finalizePaystackTransferEvent" "$FILE" || true
