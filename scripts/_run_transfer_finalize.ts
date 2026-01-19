import { Pool } from "pg";
import { finalizePaystackTransferEvent } from "../src/services/payouts.service.js";

const payoutId = process.argv[2];
const dbUrl = process.argv[3];
const actor = String(process.env.WEBHOOK_ACTOR_USER_ID ?? "").trim();

if (!payoutId) throw new Error("Missing payoutId arg");
if (!actor) throw new Error("WEBHOOK_ACTOR_USER_ID missing");

const pool = new Pool({ connectionString: dbUrl });

const asText = (v: any) => (v == null ? "" : String(v)).trim();

async function main() {
  const client = await pool.connect();
  try {
    const row = await client.query<{ gateway_payout_id: string | null }>(
      `select gateway_payout_id::text as gateway_payout_id from public.payouts where id=$1::uuid limit 1`,
      [payoutId]
    );
    if (!row.rows[0]) throw new Error("PAYOUT_NOT_FOUND_IN_DB");

    const gatewayId = asText(row.rows[0].gateway_payout_id);
    const transferCode = gatewayId || `trf_test_${payoutId.slice(0,8)}`;
    const ref = `payout_${payoutId}`;

    const event = {
      event: "transfer.success",
      data: {
        id: transferCode,
        transfer_code: transferCode,
        reference: ref,
        status: "success",
      },
    };

    await client.query("BEGIN");
    const res = await finalizePaystackTransferEvent(client as any, {
      actorUserId: actor,
      organizationId: null,
      event,
    });
    await client.query("COMMIT");

    console.log("finalize result:", res);

    const after = await client.query(
      `select id::text, status::text, gateway_payout_id, processed_at, updated_at
       from public.payouts where id=$1::uuid`,
      [payoutId]
    );
    console.log("payout after:", after.rows[0]);
  } catch (e: any) {
    try { await client.query("ROLLBACK"); } catch {}
    console.error("ERROR:", e?.message ?? e);
    process.exitCode = 1;
  } finally {
    client.release();
    await pool.end();
  }
}

main();
