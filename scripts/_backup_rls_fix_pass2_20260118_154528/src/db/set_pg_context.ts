// src/db/set_pg_context.ts
import type { PoolClient } from "pg";

export type PgContextOpts = {
  userId?: string | null;
  organizationId?: string | null;
  role?: string | null;
  eventNote?: string | null;
};

export async function setPgContext(client: PoolClient, opts: PgContextOpts) {
  const userId = opts.userId ? String(opts.userId).trim() : "";
  const orgId = opts.organizationId ? String(opts.organizationId).trim() : "";
  const role = opts.role ? String(opts.role).trim() : "";
  const eventNote = opts.eventNote ? String(opts.eventNote).trim() : "";

  // ✅ USER (support both keys)
  await client.query("select set_config('app.current_user', $1, true)", [userId]);
  await client.query("select set_config('app.user_id', $1, true)", [userId]);

  // ✅ ORG (support both keys — your SQL reads app.organization_id)
  await client.query("select set_config('app.organization_id', $1, true)", [orgId]);
  await client.query("select set_config('app.current_organization', $1, true)", [orgId]); // optional compat

  // ✅ ROLE (optional)
  await client.query("select set_config('app.role', $1, true)", [role]);

  // ✅ event note (optional)
  await client.query("select set_config('app.event_note', $1, true)", [eventNote]);
}