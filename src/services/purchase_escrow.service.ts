// src/services/purchase_escrow_release.service.ts
import type { PoolClient } from "pg";
import { setPgContext } from "../db/set_pg_context.js";
import { assertRlsContext } from "../db/rls_guard.js";

type ReleaseResult =
  | { ok: true; alreadyReleased: boolean }
  | { ok: false; error: string; message?: string };

function asText(v: any): string {
  return String(v ?? "").trim();
}

export async function releasePurchaseEscrow(
  client: PoolClient,
  args: {
    purchaseId: string;
    actorUserId: string; // REQUIRED: admin/service user (same as WEBHOOK_ACTOR_USER_ID)
    note?: string | null;
  }
): Promise<ReleaseResult> {
  const purchaseId = asText(args.purchaseId);
  if (!purchaseId) return { ok: false, error: "PURCHASE_ID_REQUIRED" };

  const actorUserId = asText(args.actorUserId);
  if (!actorUserId) return { ok: false, error: "ACTOR_USER_ID_REQUIRED" };

  // Lock + verify purchase exists
  const p = await client.query<{ id: string; organization_id: string }>(
    `
    select id::text, organization_id::text
    from public.property_purchases
    where id = $1::uuid
      and deleted_at is null
    limit 1
    for update;
    `,
    [purchaseId]
  );

  const row = p.rows?.[0];
  if (!row) return { ok: false, error: "PURCHASE_NOT_FOUND" };

  // Ensure org+admin context for RLS + defaults
  await setPgContext(client, {
    organizationId: row.organization_id,
    userId: actorUserId,
    role: "admin",
    eventNote: "purchase_escrow:release",
  });
  await assertRlsContext(client);

  // Idempotency check: if already released, do nothing
  // (keep your logic but make it tolerant)
  const already = await client.query<{ cnt: string }>(
    `
    select count(*)::text as cnt
    from public.wallet_transactions
    where reference_type = 'purchase'
      and reference_id = $1::uuid
      and txn_type::text = 'debit_escrow';
    `,
    [purchaseId]
  );

  if (Number(already.rows?.[0]?.cnt ?? "0") > 0) {
    return { ok: true, alreadyReleased: true };
  }

  try {
    await client.query(`select public.release_purchase_escrow($1::uuid, $2::text);`, [
      purchaseId,
      args.note ?? "Closing complete, released escrow",
    ]);
    return { ok: true, alreadyReleased: false };
  } catch (e: any) {
    return { ok: false, error: "ESCROW_RELEASE_FAILED", message: e?.message ?? String(e) };
  }
}