import type { PoolClient } from "pg";
import type { ApplicationRow } from "../repos/applications.repo.js";
import {
  getApplicationById,
  insertApplication,
  listApplications,
  patchApplication,
} from "../repos/applications.repo.js";

export async function createApplication(
  client: PoolClient,
  ctx: { userId: string },
  input: {
    listing_id: string;
    property_id: string;

    message?: string | null;
    monthly_income?: number | null;
    move_in_date?: string | null;

    status?: ApplicationRow["status"];
  }
): Promise<ApplicationRow> {
  return insertApplication(client, {
    listing_id: input.listing_id,
    property_id: input.property_id,
    applicant_id: ctx.userId,

    status: input.status ?? undefined,
    message: input.message ?? null,
    monthly_income: input.monthly_income ?? null,
    move_in_date: input.move_in_date ?? null,
  });
}

export async function getApplication(
  client: PoolClient,
  id: string
): Promise<ApplicationRow | null> {
  return getApplicationById(client, id);
}

export async function listAllApplications(
  client: PoolClient,
  args: {
    limit: number;
    offset: number;
    listing_id?: string;
    property_id?: string;
    applicant_id?: string;
    status?: ApplicationRow["status"];
  }
): Promise<ApplicationRow[]> {
  return listApplications(client, args);
}

export async function updateApplication(
  client: PoolClient,
  id: string,
  patch: Partial<{
    status: ApplicationRow["status"];
    message: string | null;
    monthly_income: number | null;
    move_in_date: string | null;
  }>
): Promise<ApplicationRow | null> {
  return patchApplication(client, id, patch);
}
