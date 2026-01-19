import type { PoolClient } from "pg";

type ClosePurchaseResult =
  | { ok: true; alreadyClosed: boolean; purchaseId: string }
  | { ok: false; error: string; message?: string };

export async function closePurchaseComplete(
  client: PoolClient,
  args: {
    organizationId: string;
    purchaseId: string;
    actorUserId: string;
  }
): Promise<ClosePurchaseResult> {
  const { organizationId, purchaseId, actorUserId } = args;

  // 1) Load purchase + ensure exists
  const p = await client.query(
    `
    SELECT id, organization_id, status::text AS status
    FROM public.property_purchases
    WHERE id = $1 AND organization_id = $2 AND deleted_at IS NULL
    LIMIT 1
    `,
    [purchaseId, organizationId]
  );

  if (p.rowCount === 0) {
    return { ok: false, error: "PURCHASE_NOT_FOUND", message: "Purchase not found" };
  }

  const status = String(p.rows[0].status ?? "");

  // Treat these as "closed" already (adjust to your enum)
  const alreadyClosed = ["closed", "completed", "complete"].includes(status);

  // 2) Mark purchase closed (idempotent)
  // If your schema uses a different status enum, adjust the status value here.
  if (!alreadyClosed) {
    await client.query(
      `
      UPDATE public.property_purchases
      SET status = 'closed',
          closed_at = COALESCE(closed_at, now()),
          updated_at = now()
      WHERE id = $1 AND organization_id = $2
      `,
      [purchaseId, organizationId]
    );
  }

  // 3) Audit log
  await client.query(
    `
    INSERT INTO public.audit_logs (
      organization_id, actor_user_id, action, entity_type, entity_id, payload
    ) VALUES ($1, $2, $3, $4, $5, $6::jsonb)
    `,
    [
      organizationId,
      actorUserId,
      "purchase.close_complete",
      "purchase",
      purchaseId,
      JSON.stringify({ purchaseId, previousStatus: status }),
    ]
  );

  return { ok: true, alreadyClosed, purchaseId };
}
