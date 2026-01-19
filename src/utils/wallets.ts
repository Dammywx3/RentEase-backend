import type { PoolClient } from "pg";


export async function ensureWalletAccount(
  client: PoolClient,
  args: {
    organizationId: string;
    userId: string | null;
    currency: string;
    isPlatformWallet: boolean;
  }
): Promise<string> {
  const orgId = args.organizationId;
  const userId = args.userId; // may be null
  const currency = (args.currency ?? "USD").toUpperCase();
  const isPlatformWallet = Boolean(args.isPlatformWallet);

  // 1) Try find first
  const found1 = await client.query<{ id: string }>(
    `
    SELECT id
    FROM public.wallet_accounts
    WHERE organization_id = $1::uuid
      AND user_id IS NOT DISTINCT FROM $2::uuid
      AND currency = $3::text
      AND is_platform_wallet = $4::boolean
    ORDER BY created_at ASC
    LIMIT 1;
    `,
    [orgId, userId, currency, isPlatformWallet]
  );

  if (found1.rows[0]?.id) return found1.rows[0].id;

  // 2) Try insert (idempotent)
  // IMPORTANT: $2 may be NULL; casting NULL::uuid is OK.
  const ins = await client.query<{ id: string }>(
    `
    INSERT INTO public.wallet_accounts (
      organization_id,
      user_id,
      currency,
      is_platform_wallet
    )
    VALUES (
      $1::uuid,
      $2::uuid,
      $3::text,
      $4::boolean
    )
    ON CONFLICT (organization_id, user_id, currency, is_platform_wallet)
    DO NOTHING
    RETURNING id;
    `,
    [orgId, userId, currency, isPlatformWallet]
  );

  if (ins.rows[0]?.id) return ins.rows[0].id;

  // 3) If conflict happened (someone else inserted), select again
  const found2 = await client.query<{ id: string }>(
    `
    SELECT id
    FROM public.wallet_accounts
    WHERE organization_id = $1::uuid
      AND user_id IS NOT DISTINCT FROM $2::uuid
      AND currency = $3::text
      AND is_platform_wallet = $4::boolean
    ORDER BY created_at ASC
    LIMIT 1;
    `,
    [orgId, userId, currency, isPlatformWallet]
  );

  if (found2.rows[0]?.id) return found2.rows[0].id;

  throw new Error("ensureWalletAccount: failed to create or fetch wallet_account");
}