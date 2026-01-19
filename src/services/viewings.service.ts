import type { PoolClient } from "pg";
import { insertViewing, getViewingById, listViewings, patchViewing, type ViewingRow } from "../repos/viewings.repo.js";

export async function createViewing(
  client: PoolClient,
  ctx: { userId: string },
  data: { listing_id: string; property_id: string; scheduled_at: string; view_mode?: ViewingRow["view_mode"]; status?: ViewingRow["status"]; notes?: string | null; }
) {
  return insertViewing(client, {
    listing_id: data.listing_id,
    property_id: data.property_id,
    tenant_id: ctx.userId,
    scheduled_at: data.scheduled_at,
    view_mode: data.view_mode,
    status: data.status,
    notes: data.notes ?? null,
  });
}

export async function getViewing(client: PoolClient, id: string) {
  return getViewingById(client, id);
}

export async function listAllViewings(
  client: PoolClient,
  args: { limit: number; offset: number; listing_id?: string; property_id?: string; tenant_id?: string; status?: ViewingRow["status"]; }
) {
  return listViewings(client, args);
}

export async function updateViewing(
  client: PoolClient,
  id: string,
  patch: Partial<{ scheduled_at: string; view_mode: ViewingRow["view_mode"]; status: ViewingRow["status"]; notes: string | null; }>
) {
  return patchViewing(client, id, patch);
}
