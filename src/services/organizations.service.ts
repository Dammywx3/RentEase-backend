import type { PoolClient } from "pg";
import { getOrganizationById, updateOrganizationName } from "../repos/organizations.repo.js";

export async function getMyOrganization(client: PoolClient, orgId: string) {
  return getOrganizationById(client, orgId);
}

export async function renameMyOrganization(client: PoolClient, orgId: string, name: string) {
  return updateOrganizationName(client, orgId, name);
}
