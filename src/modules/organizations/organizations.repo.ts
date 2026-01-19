import type { PoolClient } from "pg";

export type OrganizationRow = {
  id: string;
  name: string;
  created_at?: string;
  updated_at?: string;
};

export async function getOrganizationById(
  client: PoolClient,
  id: string
): Promise<OrganizationRow | null> {
  const { rows } = await client.query<OrganizationRow>(
    `
    SELECT id, name, created_at, updated_at
    FROM organizations
    WHERE id = $1
    LIMIT 1
    `,
    [id]
  );
  return rows[0] ?? null;
}

export async function updateOrganizationName(
  client: PoolClient,
  id: string,
  name: string
): Promise<OrganizationRow | null> {
  const { rows } = await client.query<OrganizationRow>(
    `
    UPDATE organizations
    SET name = $2,
        updated_at = NOW()
    WHERE id = $1
    RETURNING id, name, created_at, updated_at
    `,
    [id, name]
  );
  return rows[0] ?? null;
}
