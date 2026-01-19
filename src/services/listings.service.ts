import type { PoolClient } from "pg";
import {
  insertListing,
  getListingById,
  listListings,
  patchListing,
  type ListingRow,
} from "../repos/listings.repo.js";

export async function createListing(
  client: PoolClient,
  input: {
    property_id: string;
    kind: string;
    status?: string;

    agent_id?: string | null;
    payee_user_id: string;

    base_price: number;
    listed_price: number;

    agent_commission_percent?: number | null;
    requires_owner_approval?: boolean | null;
    is_public?: boolean | null;
    public_note?: string | null;
  }
): Promise<ListingRow> {
  return insertListing(client, input);
}

export async function getListing(
  client: PoolClient,
  id: string
): Promise<ListingRow | null> {
  return getListingById(client, id);
}

export async function listAllListings(
  client: PoolClient,
  args: { limit: number; offset: number }
): Promise<ListingRow[]> {
  return listListings(client, args);
}

export async function updateListing(
  client: PoolClient,
  id: string,
  patch: Partial<{
    status: string;
    agent_id: string | null;
    payee_user_id: string;
    base_price: number;
    listed_price: number;
    agent_commission_percent: number | null;
    requires_owner_approval: boolean | null;
    is_public: boolean | null;
    public_note: string | null;
  }>
): Promise<ListingRow | null> {
  return patchListing(client, id, patch);
}
