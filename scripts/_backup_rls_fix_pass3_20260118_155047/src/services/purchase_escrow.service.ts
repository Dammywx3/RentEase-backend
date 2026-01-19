import type { PoolClient } from "pg";

type ReleaseResult =
  | { ok: true; alreadyReleased: boolean }
  | { ok: false; error: string; message?: string };

export async function releasePurchaseEscrow(
  client: PoolClient,
  args: {
    purchaseId: string;
    note?: string | null;
  }
): Promise<ReleaseResult> {
  const purchaseId = String(args.purchaseId || "").trim();
  if (!purchaseId) return { ok: false, error: "PURCHASE_ID_REQUIRED" };

  // Lock + verify purchase exists
  const p = await client.query<{ id: string; organization_id: string }>(
    `
    SELECT id::text, organization_id::text
    FROM public.property_purchases
    WHERE id = $1::uuid
      AND deleted_at IS NULL
    LIMIT 1
    FOR UPDATE;
    `,
    [purchaseId]
  );

  const row = p.rows[0];
  if (!row) return { ok: false, error: "PURCHASE_NOT_FOUND" };

  // Ensure org context for DB defaults/RLS/wallet helpers
  await client.query("select set_config('app.organization_id', $1, true)", [row.organization_id]);

  // Idempotency check (same as SQL function)
  const already = await client.query<{ cnt: string }>(
    `
    SELECT count(*)::text as cnt
    FROM public.wallet_transactions
    WHERE reference_type='purchase'
      AND reference_id=$1::uuid
      AND txn_type::text='debit_escrow';
    `,
    [purchaseId]
  );

  if (Number(already.rows[0]?.cnt ?? "0") > 0) {
    return { ok: true, alreadyReleased: true };
  }

  try {
    await client.query(`SELECT public.release_purchase_escrow($1::uuid, $2::text);`, [
      purchaseId,
      args.note ?? "Closing complete, released escrow",
    ]);
    return { ok: true, alreadyReleased: false };
  } catch (e: any) {
    return { ok: false, error: "ESCROW_RELEASE_FAILED", message: e?.message ?? String(e) };
  }
}
