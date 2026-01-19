#!/usr/bin/env bash
set -euo pipefail

cat > src/repos/listings.repo.ts <<'TS'
import type { PoolClient } from "pg";

export type ListingRow = {
  id: string;
  organization_id: string | null;

  property_id: string;
  kind: string;
  status: string | null;

  created_by: string | null;
  agent_id: string | null;
  payee_user_id: string | null;

  base_price: string;
  listed_price: string;

  agent_commission_percent: string | null;
  platform_fee_percent: string | null;
  platform_fee_basis: string | null;

  requires_owner_approval: boolean | null;
  owner_approved: boolean | null;
  owner_approved_at: string | null;
  owner_approved_by: string | null;

  is_public: boolean | null;
  public_note: string | null;

  created_at: string;
  updated_at: string;
  deleted_at: string | null;
};

type CreateListingInput = {
  property_id: string;
  kind: string;

  // IMPORTANT: optional — if not provided, DB default (draft) should apply
  status?: string | null;

  agent_id?: string | null;
  payee_user_id: string;

  base_price: number;
  listed_price: number;

  agent_commission_percent?: number | null;

  requires_owner_approval?: boolean | null;
  is_public?: boolean | null;
  public_note?: string | null;
};

export async function insertListing(
  client: PoolClient,
  data: CreateListingInput
): Promise<ListingRow> {
  // Build dynamic INSERT so we DO NOT pass status=null
  // (passing null overrides DB default)
  const cols: string[] = [
    "organization_id",
    "property_id",
    "kind",
    "created_by",
    "agent_id",
    "payee_user_id",
    "base_price",
    "listed_price",
    "agent_commission_percent",
    "requires_owner_approval",
    "is_public",
    "public_note",
  ];

  const vals: string[] = [
    "current_organization_uuid()",
    "$1",
    "$2",
    "current_user_uuid()",
    "$3",
    "$4",
    "$5",
    "$6",
    "$7",
    "$8",
    "$9",
    "$10",
  ];

  const params: any[] = [
    data.property_id,
    data.kind,
    data.agent_id ?? null,
    data.payee_user_id,
    data.base_price,
    data.listed_price,
    data.agent_commission_percent ?? null,
    data.requires_owner_approval ?? null,
    data.is_public ?? null,
    data.public_note ?? null,
  ];

  // ✅ Only include status if explicitly provided (not null/undefined)
  if (data.status !== undefined && data.status !== null) {
    cols.splice(3, 0, "status"); // put near kind (cosmetic)
    vals.splice(3, 0, `$${params.length + 1}`);
    params.push(data.status);
  }

  const sql = `
    INSERT INTO property_listings (${cols.join(", ")})
    VALUES (${vals.join(", ")})
    RETURNING *
  `;

  const { rows } = await client.query<ListingRow>(sql, params);
  return rows[0]!;
}

export async function getListingById(
  client: PoolClient,
  id: string
): Promise<ListingRow | null> {
  const { rows } = await client.query<ListingRow>(
    `
    SELECT *
    FROM property_listings
    WHERE id = $1 AND deleted_at IS NULL
    LIMIT 1
    `,
    [id]
  );
  return rows[0] ?? null;
}

export async function listListings(
  client: PoolClient,
  args: { limit: number; offset: number }
): Promise<ListingRow[]> {
  const { rows } = await client.query<ListingRow>(
    `
    SELECT *
    FROM property_listings
    WHERE deleted_at IS NULL
    ORDER BY created_at DESC
    LIMIT $1 OFFSET $2
    `,
    [args.limit, args.offset]
  );
  return rows;
}
TS

echo "✅ Fixed listings.repo.ts (status default will now apply)"
