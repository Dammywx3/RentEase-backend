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

type InsertListingInput = {
  property_id: string;
  kind: string;

  // IMPORTANT: omit status column if undefined, to let DB default 'draft' apply
  status?: string;

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
  data: InsertListingInput
): Promise<ListingRow> {
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

  const vals: any[] = [
    // RLS helpers
    "current_organization_uuid()",
    data.property_id,
    data.kind,
    "current_user_uuid()",
    data.agent_id ?? null,
    data.payee_user_id,
    data.base_price,
    data.listed_price,
    data.agent_commission_percent ?? null,
    data.requires_owner_approval ?? null,
    data.is_public ?? null,
    data.public_note ?? null,
  ];

  // status: ONLY include if provided, else let default 'draft' apply
  if (typeof data.status !== "undefined") {
    cols.splice(3, 0, "status"); // after kind
    vals.splice(3, 0, data.status);
  }

  // Build SQL with placeholders, but allow "current_*_uuid()" as raw
  const placeholders: string[] = [];
  const params: any[] = [];
  let p = 1;

  for (const v of vals) {
    if (v === "current_organization_uuid()" || v === "current_user_uuid()") {
      placeholders.push(v);
    } else {
      placeholders.push(`$${p++}`);
      params.push(v);
    }
  }

  const { rows } = await client.query<ListingRow>(
    `
    INSERT INTO property_listings (${cols.join(", ")})
    VALUES (${placeholders.join(", ")})
    RETURNING *
    `,
    params
  );

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

export async function patchListing(
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
  const sets: string[] = ["updated_at = now()"];
  const params: any[] = [];
  let i = 1;

  for (const [k, v] of Object.entries(patch)) {
    sets.push(`${k} = $${i++}`);
    params.push(v);
  }

  params.push(id);

  const { rows } = await client.query<ListingRow>(
    `
    UPDATE property_listings
    SET ${sets.join(", ")}
    WHERE id = $${i} AND deleted_at IS NULL
    RETURNING *
    `,
    params
  );

  return rows[0] ?? null;
}
