// src/db/rls_guard.ts
import type { PoolClient } from "pg";

export async function assertRlsContext(client: PoolClient) {
  const { rows } = await client.query<{ org_id: string | null; user_id: string | null }>(`
    select
      public.current_organization_uuid()::text as org_id,
      public.current_user_uuid()::text as user_id
  `);

  const orgId = rows?.[0]?.org_id ?? null;
  const userId = rows?.[0]?.user_id ?? null;

  if (!orgId) {
    const e: any = new Error("RLS_CONTEXT_MISSING: organization not set (setPgContext not applied)");
    e.code = "RLS_CONTEXT_MISSING_ORG";
    throw e;
  }

  return { orgId, userId };
}

export async function assertRlsContextWithUser(client: PoolClient) {
  const ctx = await assertRlsContext(client);
  if (!ctx.userId) {
    const e: any = new Error("RLS_CONTEXT_MISSING: user not set (setPgContext not applied)");
    e.code = "RLS_CONTEXT_MISSING_USER";
    throw e;
  }
  return ctx;
}
