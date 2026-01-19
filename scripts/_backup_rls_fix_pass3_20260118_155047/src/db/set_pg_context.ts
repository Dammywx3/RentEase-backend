import type { PoolClient } from "pg";

export type PgContextlBool = boolean;

export type PgContextOpts = {
  userId?: string | null;
  organizationId?: string | null;
  role?: string | null;
  eventNote?: string | null;
};

/**
 * Centralized RLS/session context setter.
 *
 * Uses SET LOCAL (is_local=true) so values are scoped to the current transaction
 * when called after BEGIN. This prevents pool leakage.
 *
 * We set multiple aliases because different parts of the app / policies / triggers
 * may reference different keys.
 */
export async function setPgContext(client: PoolClient, opts: PgContextOpts) {
  const userId = String(opts.userId ?? "").trim();
  const organizationId = String(opts.organizationId ?? "").trim();
  const role = String(opts.role ?? "").trim();
  const eventNote = String(opts.eventNote ?? "").trim();

  // Helper for SET LOCAL
  async function setKey(key: string, value: string) {
    // must be called inside transaction if you want LOCAL behavior
    await client.query("SELECT set_config($1, $2, true);", [key, value]);
  }

  // --- Org keys
  if (organizationId) {
    await setKey("app.organization_id", organizationId);
    await setKey("app.current_organization", organizationId);
    await setKey("request.header.x_organization_id", organizationId);
    await setKey("rentease.organization_id", organizationId);
  } else {
    // keep keys predictable if someone checks existence
    await setKey("app.organization_id", "");
    await setKey("app.current_organization", "");
    await setKey("request.header.x_organization_id", "");
    await setKey("rentease.organization_id", "");
  }

  // --- User keys
  if (userId) {
    await setKey("app.user_id", userId);
    await setKey("app.current_user", userId);
    await setKey("request.jwt.claim.sub", userId);
    await setKey("rentease.user_id", userId);
  } else {
    await setKey("app.user_id", "");
    await setKey("app.current_user", "");
    await setKey("request.jwt.claim.sub", "");
    await setKey("rentease.user_id", "");
  }

  // --- Role keys (some policies/triggers may read these)
  if (role) {
    await setKey("request.user_role", role);
    await setKey("app.user_role", role);
    await setKey("rentease.user_role", role);
  } else {
    await setKey("request.user_role", "");
    await setKey("app.user_role", "");
    await setKey("rentease.user_role", "");
  }

  // --- Optional event note (good for audit/debug)
  if (eventNote) {
    // Avoid super long config values
    const clean = eventNote.slice(0, 200);
    await setKey("app.event_note", clean);
    await setKey("rentease.event_note", clean);
  } else {
    await setKey("app.event_note", "");
    await setKey("rentease.event_note", "");
  }
}
