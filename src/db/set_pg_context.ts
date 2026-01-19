import type { PoolClient } from "pg";

/**
 * PgContextOpts (PARTIAL / SAFE)
 * - Only sets keys you provide (does NOT overwrite others with empty strings).
 * - Uses set_config(..., true) which is LOCAL to the current transaction when called after BEGIN.
 */
export type PgContextOpts = {
  userId?: string | null;
  organizationId?: string | null;
  role?: string | null;
  eventNote?: string | null;
};

function clean(v: unknown): string | null {
  const s = String(v ?? "").trim();
  return s ? s : null;
}

async function setLocal(client: PoolClient, key: string, value: string) {
  // LOCAL to tx if called after BEGIN
  await client.query("SELECT set_config($1, $2, true)", [key, value]);
}

export async function setPgContext(client: PoolClient, opts: PgContextOpts) {
  const userId = clean(opts.userId);
  const organizationId = clean(opts.organizationId);
  const role = clean(opts.role);
  const eventNote = clean(opts.eventNote);

  // ---- Organization (set all aliases your policies might use) ----
  if (organizationId) {
    await setLocal(client, "request.header.x_organization_id", organizationId);
    await setLocal(client, "app.organization_id", organizationId);
    await setLocal(client, "app.current_organization", organizationId);
    await setLocal(client, "app.current_organization_id", organizationId);
  }

  // ---- User ----
  if (userId) {
    await setLocal(client, "request.jwt.claim.sub", userId);
    await setLocal(client, "app.user_id", userId);
    await setLocal(client, "app.current_user", userId);
    await setLocal(client, "app.current_user_id", userId);
  }

  // ---- Role ----
  if (role) {
    await setLocal(client, "request.user_role", role);
    await setLocal(client, "app.user_role", role);
    await setLocal(client, "rentease.user_role", role);
  }

  // ---- Event note (optional, only if provided) ----
  if (eventNote) {
    await setLocal(client, "app.event_note", eventNote);
  }
}

export default setPgContext;
