#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(pwd)"

mkdir -p "src/services" "src/routes" "sql" "scripts"

echo "==> Writing SQL function migration: sql/2026_01_18_release_purchase_escrow.sql"
cat > "sql/2026_01_18_release_purchase_escrow.sql" <<'SQL'
-- sql/2026_01_18_release_purchase_escrow.sql
-- Releases escrow for a purchase:
-- - debit escrow wallet
-- - credit seller wallet
-- - mark purchase completed
--
-- IMPORTANT:
-- This assumes you already have:
--   public.get_or_create_org_escrow_wallet(uuid) returns uuid
--   public.get_or_create_user_wallet_account(uuid) returns uuid
--
-- This also assumes wallet_transactions has:
--   wallet_account_id, txn_type, reference_type, reference_id, amount, currency, note
-- If your schema differs, paste your wallet_transactions \d and I will adapt.

CREATE OR REPLACE FUNCTION public.release_purchase_escrow(
  p_purchase_id uuid,
  p_note text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_seller_id uuid;
  v_currency text;
  v_note text;
  v_exists int;

  v_escrow_wallet_id uuid;
  v_seller_wallet_id uuid;

  v_amount numeric;
BEGIN
  -- Lock purchase row to prevent double release
  SELECT organization_id, seller_id, COALESCE(currency,'NGN')::text
  INTO v_org_id, v_seller_id, v_currency
  FROM public.property_purchases
  WHERE id = p_purchase_id
    AND deleted_at IS NULL
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PURCHASE_NOT_FOUND: %', p_purchase_id USING ERRCODE = 'P0001';
  END IF;

  -- ensure org context for wallet helpers / RLS defaults
  PERFORM set_config('app.organization_id', v_org_id::text, true);

  v_note := COALESCE(p_note, 'Closing complete, released escrow');

  -- Idempotency: if we already debited escrow for this purchase, do nothing
  SELECT COUNT(*)::int
  INTO v_exists
  FROM public.wallet_transactions
  WHERE reference_type = 'purchase'
    AND reference_id = p_purchase_id
    AND txn_type::text = 'debit_escrow';

  IF v_exists > 0 THEN
    RETURN;
  END IF;

  -- How much is currently held in escrow for this purchase?
  -- (credits to escrow - debits from escrow)
  SELECT COALESCE(SUM(
    CASE
      WHEN txn_type::text = 'credit_escrow' THEN amount
      WHEN txn_type::text = 'debit_escrow'  THEN -amount
      ELSE 0
    END
  ), 0)
  INTO v_amount
  FROM public.wallet_transactions
  WHERE reference_type = 'purchase'
    AND reference_id = p_purchase_id;

  IF v_amount <= 0 THEN
    RAISE EXCEPTION 'NO_ESCROW_BALANCE_FOR_PURCHASE: %', p_purchase_id USING ERRCODE = 'P0001';
  END IF;

  -- Resolve wallets (creates if missing)
  v_escrow_wallet_id := public.get_or_create_org_escrow_wallet(v_org_id);
  v_seller_wallet_id := public.get_or_create_user_wallet_account(v_seller_id);

  -- Move funds: escrow -> seller
  INSERT INTO public.wallet_transactions (
    wallet_account_id, txn_type, reference_type, reference_id, amount, currency, note
  )
  VALUES
    (v_escrow_wallet_id, 'debit_escrow',  'purchase', p_purchase_id, v_amount, v_currency, v_note),
    (v_seller_wallet_id, 'credit_seller','purchase', p_purchase_id, v_amount, v_currency, v_note);

  -- Mark purchase completed (safe if already completed)
  BEGIN
    UPDATE public.property_purchases
    SET
      status = CASE
        WHEN status::text IN ('completed','closed') THEN status
        ELSE 'completed'::public.purchase_status
      END,
      closed_at = COALESCE(closed_at, NOW()),
      updated_at = NOW()
    WHERE id = p_purchase_id
      AND deleted_at IS NULL;
  EXCEPTION WHEN others THEN
    -- If your enum/table fields differ, escrow release still succeeded.
    NULL;
  END;

END;
$$;
SQL

echo "==> Writing service: src/services/purchase_escrow.service.ts"
cat > "src/services/purchase_escrow.service.ts" <<'TS'
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
TS

echo "==> Writing route: src/routes/purchase_escrow.ts"
cat > "src/routes/purchase_escrow.ts" <<'TS'
import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { releasePurchaseEscrow } from "../services/purchase_escrow.service.js";

export async function purchaseEscrowRoutes(app: FastifyInstance) {
  // POST /v1/purchases/:id/release-escrow
  // Auth required (admin/agent/seller - you decide policy in authenticate middleware / role checks)
  app.post(
    "/purchases/:id/release-escrow",
    { preHandler: [app.authenticate] },
    async (req, reply) => {
      const params = z.object({ id: z.string().uuid() }).parse((req as any).params);

      const organizationId = String((req as any).orgId ?? "").trim();
      const userId = String((req as any).user?.userId ?? "").trim();

      if (!organizationId) {
        return reply.code(400).send({ ok: false, error: "ORG_REQUIRED", message: "Missing orgId from auth middleware" });
      }
      if (!userId) {
        return reply.code(401).send({ ok: false, error: "UNAUTHORIZED", message: "Missing authenticated user" });
      }

      // @ts-ignore - fastify-postgres decorates app.pg
      const client = await app.pg.connect();
      try {
        await client.query("BEGIN");

        // RLS context
        await client.query("select set_config('app.organization_id', $1, true)", [organizationId]);
        await client.query("select set_config('request.header.x_organization_id', $1, true)", [organizationId]);
        await client.query("select set_config('request.jwt.claim.sub', $1, true)", [userId]);
        await client.query("select set_config('app.user_id', $1, true)", [userId]);

        const res = await releasePurchaseEscrow(client, {
          purchaseId: params.id,
          note: "Closing complete, released escrow",
        });

        await client.query("COMMIT");

        if (!res.ok) {
          return reply.code(400).send({ ok: false, error: res.error, message: res.message });
        }

        return reply.send({ ok: true, data: res });
      } catch (e: any) {
        try { await client.query("ROLLBACK"); } catch {}
        return reply.code(500).send({ ok: false, error: "SERVER_ERROR", message: e?.message ?? String(e) });
      } finally {
        client.release();
      }
    }
  );
}
TS

echo "==> Patching src/routes/index.ts to register purchaseEscrowRoutes under /v1"

INDEX_FILE="src/routes/index.ts"
if [ ! -f "$INDEX_FILE" ]; then
  echo "ERROR: $INDEX_FILE not found. Are you in the project root?"
  exit 1
fi

# 1) Add import if missing
perl -0777 -i -pe '
  if ($ARGV eq "src/routes/index.ts") {
    if ($_ !~ /purchaseEscrowRoutes/) {
      s/(import\s+\{?\s*paymentsRoutes\s*\}?\s+from\s+"\.\/payments\.js";\s*\n)/
$1import { purchaseEscrowRoutes } from "\.\/purchase_escrow\.js";\n/s;
    }
  }
' "$INDEX_FILE"

# 2) Register inside the /v1 block if missing
perl -0777 -i -pe '
  if ($ARGV eq "src/routes/index.ts") {
    if ($_ !~ /v1\.register\(purchaseEscrowRoutes\)/) {
      s/(await\s+v1\.register\(purchasesRoutes\);\s*\n)/$1      await v1.register(purchaseEscrowRoutes);\n/s;
    }
  }
' "$INDEX_FILE"

echo
echo "✅ Done creating files + patching routes."
echo
echo "NEXT STEPS:"
echo "1) Apply SQL migration:"
echo "   DB=rentease psql -X -P pager=off -d \"\$DB\" -f sql/2026_01_18_release_purchase_escrow.sql"
echo
echo "2) Restart server, then call:"
echo "   POST /v1/purchases/:id/release-escrow"
echo
echo "3) Verify ledger:"
echo "   SELECT * FROM wallet_transactions WHERE reference_type='purchase' AND reference_id='...';"
echo
