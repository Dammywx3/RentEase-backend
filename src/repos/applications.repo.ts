import type { PoolClient } from "pg";

export type ApplicationRow = {
  id: string;
  listing_id: string;
  property_id: string;
  applicant_id: string;

  status: "pending" | "approved" | "rejected" | "withdrawn" | null;

  message: string | null;
  monthly_income: string | null;

  // date-only string like "2026-02-01"
  move_in_date: string | null;

  created_at: string;
  updated_at: string;
};

export async function insertApplication(
  client: PoolClient,
  data: {
    listing_id: string;
    property_id: string;
    applicant_id: string;

    status?: ApplicationRow["status"];
    message?: string | null;
    monthly_income?: number | null;

    // accept YYYY-MM-DD
    move_in_date?: string | null;
  }
): Promise<ApplicationRow> {
  try {
    const { rows } = await client.query<ApplicationRow>(
  `
  INSERT INTO rental_applications (
    listing_id,
    property_id,
    applicant_id,
    status,
    message,
    monthly_income,
    move_in_date
  )
  VALUES (
    $1,$2,$3,
    COALESCE($4, 'pending'::application_status),
    $5,$6,
    $7::date
  )
  ON CONFLICT (listing_id, applicant_id)
  DO UPDATE SET
    message = EXCLUDED.message,
    monthly_income = EXCLUDED.monthly_income,
    move_in_date = EXCLUDED.move_in_date,
    updated_at = now()
  RETURNING *;
  `,
  [
    data.listing_id,
    data.property_id,
    data.applicant_id,
    data.status ?? null,
    data.message ?? null,
    data.monthly_income ?? null,
    data.move_in_date ?? null,
  ]
);
return rows[0]!;
  } catch (err: any) {
    // Duplicate application for same listing+applicant (your partial unique index)
    if (err?.code === "23505") {
      const { rows } = await client.query<ApplicationRow>(
        `
        SELECT *
        FROM rental_applications
        WHERE listing_id = $1
          AND applicant_id = $2
          AND status = ANY (ARRAY['pending'::application_status, 'approved'::application_status])
        ORDER BY created_at DESC
        LIMIT 1
        `,
        [data.listing_id, data.applicant_id]
      );

      // If found, return existing instead of crashing
      if (rows[0]) return rows[0];
    }

    throw err;
  }
}

export async function getApplicationById(
  client: PoolClient,
  id: string
): Promise<ApplicationRow | null> {
  const { rows } = await client.query<ApplicationRow>(
    `
    SELECT *
    FROM rental_applications
    WHERE id = $1
    LIMIT 1
    `,
    [id]
  );
  return rows[0] ?? null;
}

export async function listApplications(
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
  const where: string[] = ["1=1"];
  const params: any[] = [];
  let i = 1;

  if (args.listing_id) {
    where.push(`listing_id = $${i++}`);
    params.push(args.listing_id);
  }
  if (args.property_id) {
    where.push(`property_id = $${i++}`);
    params.push(args.property_id);
  }
  if (args.applicant_id) {
    where.push(`applicant_id = $${i++}`);
    params.push(args.applicant_id);
  }
  if (args.status) {
    where.push(`status = $${i++}`);
    params.push(args.status);
  }

  params.push(args.limit);
  const limitIdx = i++;
  params.push(args.offset);
  const offsetIdx = i++;

  const { rows } = await client.query<ApplicationRow>(
    `
    SELECT *
    FROM rental_applications
    WHERE ${where.join(" AND ")}
    ORDER BY created_at DESC
    LIMIT $${limitIdx} OFFSET $${offsetIdx}
    `,
    params
  );

  return rows;
}

export async function patchApplication(
  client: PoolClient,
  id: string,
  patch: Partial<{
    status: ApplicationRow["status"];
    message: string | null;
    monthly_income: number | null;
    move_in_date: string | null; // YYYY-MM-DD
  }>
): Promise<ApplicationRow | null> {
  const sets: string[] = ["updated_at = now()"];
  const params: any[] = [];
  let i = 1;

  for (const [k, v] of Object.entries(patch)) {
    if (k === "move_in_date") {
      sets.push(`${k} = $${i++}::date`);
      params.push(v);
      continue;
    }
    sets.push(`${k} = $${i++}`);
    params.push(v);
  }

  params.push(id);

  const { rows } = await client.query<ApplicationRow>(
    `
    UPDATE rental_applications
    SET ${sets.join(", ")}
    WHERE id = $${i}
    RETURNING *
    `,
    params
  );

  return rows[0] ?? null;
}