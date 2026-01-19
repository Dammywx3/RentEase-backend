import type { PoolClient } from "pg";

export type PropertyRow = {
  id: string;
  organization_id: string;

  owner_id: string | null;
  owner_external_name: string | null;
  owner_external_phone: string | null;
  owner_external_email: string | null;

  default_agent_id: string | null;

  title: string;
  description: string | null;

  type: string;
  base_price: string; // pg returns numeric as string
  currency: string | null;

  address_line1: string | null;
  address_line2: string | null;
  city: string | null;
  state: string | null;
  country: string | null;
  postal_code: string | null;

  latitude: string | null;
  longitude: string | null;

  bedrooms: number | null;
  bathrooms: number | null;
  square_meters: string | null;
  year_built: number | null;

  amenities: string[] | null;

  status: string | null;
  verification_status: string | null;

  slug: string | null;
  view_count: number | null;

  created_at: string;
  updated_at: string;

  created_by: string | null;
  updated_by: string | null;
};

type InsertPropertyInput = {
  owner_id?: string | null;
  owner_external_name?: string | null;
  owner_external_phone?: string | null;
  owner_external_email?: string | null;
  default_agent_id?: string | null;

  title: string;
  description?: string | null;

  type: string;
  base_price: number;
  currency?: string | null; // ✅ undefined => use DB default ('USD')

  address_line1?: string | null;
  address_line2?: string | null;
  city?: string | null;
  state?: string | null;
  country?: string | null;
  postal_code?: string | null;

  latitude?: number | null;
  longitude?: number | null;

  bedrooms?: number | null;
  bathrooms?: number | null;
  square_meters?: number | null;
  year_built?: number | null;

  amenities?: string[] | null;

  status?: string | null; // ✅ undefined => DB default ('available')
  verification_status?: string | null; // ✅ undefined => DB default ('pending')

  slug?: string | null;

  created_by?: string | null;
  updated_by?: string | null;
};

export async function insertProperty(
  client: PoolClient,
  data: InsertPropertyInput
): Promise<PropertyRow> {
  // ✅ Only include columns that are actually provided.
  // If a value is undefined => omit => DB default applies.
  // If a value is null => included => stores NULL.

  const cols: string[] = [];
  const vals: string[] = [];
  const params: any[] = [];
  let i = 1;

  const add = (col: string, value: any) => {
    if (value === undefined) return; // omit to keep DB default
    cols.push(col);
    vals.push(`$${i++}`);
    params.push(value);
  };

  // Required
  add("title", data.title);
  add("type", data.type);
  add("base_price", data.base_price);

  // Optional (with defaults in DB)
  add("currency", data.currency);

  // Ownership
  add("owner_id", data.owner_id);
  add("owner_external_name", data.owner_external_name);
  add("owner_external_phone", data.owner_external_phone);
  add("owner_external_email", data.owner_external_email);
  add("default_agent_id", data.default_agent_id);

  // Details
  add("description", data.description);
  add("address_line1", data.address_line1);
  add("address_line2", data.address_line2);
  add("city", data.city);
  add("state", data.state);
  add("country", data.country);
  add("postal_code", data.postal_code);

  // Geo
  add("latitude", data.latitude);
  add("longitude", data.longitude);

  // Specs
  add("bedrooms", data.bedrooms);
  add("bathrooms", data.bathrooms);
  add("square_meters", data.square_meters);
  add("year_built", data.year_built);

  // Arrays / enums
  add("amenities", data.amenities);
  add("status", data.status);
  add("verification_status", data.verification_status);

  // Slug + audit
  add("slug", data.slug);
  add("created_by", data.created_by);
  add("updated_by", data.updated_by);

  const sql =
    cols.length === 0
      ? `INSERT INTO properties DEFAULT VALUES RETURNING *`
      : `
        INSERT INTO properties (${cols.join(", ")})
        VALUES (${vals.join(", ")})
        RETURNING *
      `;

  const { rows } = await client.query<PropertyRow>(sql, params);
  return rows[0]!;
}

export async function getPropertyById(
  client: PoolClient,
  id: string
): Promise<PropertyRow | null> {
  const { rows } = await client.query<PropertyRow>(
    `
    SELECT *
    FROM properties
    WHERE id = $1 AND deleted_at IS NULL
    LIMIT 1
    `,
    [id]
  );
  return rows[0] ?? null;
}

export async function listProperties(
  client: PoolClient,
  args: {
    limit: number;
    offset: number;
    status?: string;
    type?: string;
    city?: string;
  }
): Promise<PropertyRow[]> {
  const where: string[] = ["deleted_at IS NULL"];
  const params: any[] = [];
  let i = 1;

  if (args.status) {
    where.push(`status = $${i++}`);
    params.push(args.status);
  }
  if (args.type) {
    where.push(`type = $${i++}`);
    params.push(args.type);
  }
  if (args.city) {
    where.push(`city ILIKE $${i++}`);
    params.push(`%${args.city}%`);
  }

  params.push(args.limit);
  const limitIdx = i++;
  params.push(args.offset);
  const offsetIdx = i++;

  const { rows } = await client.query<PropertyRow>(
    `
    SELECT *
    FROM properties
    WHERE ${where.join(" AND ")}
    ORDER BY created_at DESC
    LIMIT $${limitIdx} OFFSET $${offsetIdx}
    `,
    params
  );

  return rows;
}

export async function patchProperty(
  client: PoolClient,
  id: string,
  patch: Partial<{
    owner_id: string | null;
    owner_external_name: string | null;
    owner_external_phone: string | null;
    owner_external_email: string | null;
    default_agent_id: string | null;

    title: string;
    description: string | null;
    type: string;

    base_price: number;
    currency: string | null;

    address_line1: string | null;
    address_line2: string | null;
    city: string | null;
    state: string | null;
    country: string | null;
    postal_code: string | null;

    latitude: number | null;
    longitude: number | null;

    bedrooms: number | null;
    bathrooms: number | null;
    square_meters: number | null;
    year_built: number | null;

    amenities: string[] | null;

    status: string | null;
    verification_status: string | null;
    slug: string | null;

    updated_by: string | null;
  }>
): Promise<PropertyRow | null> {
  const sets: string[] = ["updated_at = now()"];
  const params: any[] = [];
  let i = 1;

  for (const [k, v] of Object.entries(patch)) {
    if (v === undefined) continue; // ✅ don't accidentally set NULL
    sets.push(`${k} = $${i++}`);
    params.push(v);
  }

  params.push(id);

  const { rows } = await client.query<PropertyRow>(
    `
    UPDATE properties
    SET ${sets.join(", ")}
    WHERE id = $${i} AND deleted_at IS NULL
    RETURNING *
    `,
    params
  );

  return rows[0] ?? null;
}