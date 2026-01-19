import type { PoolClient } from "pg";
import { ensureWalletAccount } from "../utils/wallets.js";

/**
 * Find oldest platform wallet for org (you currently have 2; we pick earliest).
 */
export async function getPlatformWalletId(
  client: PoolClient,
  organizationId: string
): Promise<string | null> {
  const { rows } = await client.query<{ id: string }>(
    `
    SELECT id
    FROM public.wallet_accounts
    WHERE organization_id = $1::uuid
      AND is_platform_wallet = true
    ORDER BY created_at ASC
    LIMIT 1;
    `,
    [organizationId]
  );
  return rows[0]?.id ?? null;
}

/**
 * Credit platform fee into platform wallet.
 * Uses txn_type = credit_platform_fee.
 */
export async function creditPlatformFee(
  client: PoolClient,
  args: {
    organizationId: string;
    referenceType: "rent_invoice" | "payment" | "purchase" | "subscription";
    referenceId: string;
    amount: number;
    currency: string;
    note: string;
  }
) {
  if (!args.amount || args.amount <= 0) return;

  const platformWalletId = await getPlatformWalletId(client, args.organizationId);
  if (!platformWalletId) return;

  await client.query(
    `
    INSERT INTO public.wallet_transactions (
      organization_id,
      wallet_account_id,
      txn_type,
      reference_type,
      reference_id,
      amount,
      currency,
      note
    )
    VALUES (
      $1::uuid,
      $2::uuid,
      'credit_platform_fee'::wallet_transaction_type,
      $3::text,
      $4::uuid,
      $5::numeric,
      $6::text,
      $7::text
    )
    ON CONFLICT DO NOTHING;
    `,
    [
      args.organizationId,
      platformWalletId,
      args.referenceType,
      args.referenceId,
      args.amount,
      args.currency,
      args.note,
    ]
  );
}

/**
 * Credit payee (landlord) wallet.
 * Uses txn_type = credit_payee.
 */
export async function creditPayee(
  client: PoolClient,
  args: {
    organizationId: string;
    payeeUserId: string;
    referenceType: "rent_invoice" | "payment" | "purchase" | "subscription";
    referenceId: string;
    amount: number;
    currency: string;
    note: string;
  }
) {
  if (!args.amount || args.amount <= 0) return;

  const payeeWalletId = await ensureWalletAccount(client, {
    organizationId: args.organizationId,
    userId: args.payeeUserId,
    currency: args.currency,
    isPlatformWallet: false,
  });

  await client.query(
    `
    INSERT INTO public.wallet_transactions (
      organization_id,
      wallet_account_id,
      txn_type,
      reference_type,
      reference_id,
      amount,
      currency,
      note
    )
    VALUES (
      $1::uuid,
      $2::uuid,
      'credit_payee'::wallet_transaction_type,
      $3::text,
      $4::uuid,
      $5::numeric,
      $6::text,
      $7::text
    )
    ON CONFLICT DO NOTHING;
    `,
    [
      args.organizationId,
      payeeWalletId,
      args.referenceType,
      args.referenceId,
      args.amount,
      args.currency,
      args.note,
    ]
  );
}

/**
 * Refund / reversal helpers
 * These mirror creditPayee / creditPlatformFee but write debit_* txn types.
 * Assumes wallet_transaction_type enum includes debit_payee and debit_platform_fee.
 */



/* ------------------------------------------------------------------
 * Refund helpers (shared insert + debit txns)
 * ------------------------------------------------------------------ */

type WalletTxnInsertArgs = {
  organizationId: string;
  walletAccountId: string;
  txnType:
    | "credit_platform_fee"
    | "credit_payee"
    | "debit_platform_fee"
    | "debit_payee";
  amount: number;
  currency: string;
  referenceType: string;
  referenceId: string;
};

/**
 * Insert a wallet transaction in a single place.
 * Idempotency: relies on your existing unique constraints (if any),
 * but still safe to call because we use ON CONFLICT DO NOTHING.
 */
export async function insertWalletTransaction(
  client: PoolClient,
  args: WalletTxnInsertArgs
): Promise<{ id: string | null }> {
  const { rows } = await client.query<{ id: string }>(
    `
    INSERT INTO public.wallet_transactions (
      organization_id,
      wallet_account_id,
      txn_type,
      amount,
      currency,
      reference_type,
      reference_id,
      created_at,
      updated_at
    )
    VALUES (
      $1::uuid,
      $2::uuid,
      $3::wallet_transaction_type,
      $4::numeric,
      $5::varchar(3),
      $6::text,
      $7::uuid,
      NOW(),
      NOW()
    )
    ON CONFLICT DO NOTHING
    RETURNING id::text AS id;
    `,
    [
      args.organizationId,
      args.walletAccountId,
      args.txnType,
      args.amount,
      args.currency,
      args.referenceType,
      args.referenceId,
    ]
  );

  return { id: rows?.[0]?.id ?? null };
}

async function getPlatformWalletAccountId(
  client: PoolClient,
  organizationId: string
): Promise<string> {
  const { rows } = await client.query<{ id: string }>(
    `
    SELECT id::text AS id
    FROM public.wallet_accounts
    WHERE organization_id = $1::uuid
      AND is_platform_wallet = true
    ORDER BY created_at ASC
    LIMIT 1;
    `,
    [organizationId]
  );

  const id = rows?.[0]?.id;
  if (!id) {
    const e: any = new Error("Platform wallet account not found");
    e.code = "PLATFORM_WALLET_NOT_FOUND";
    throw e;
  }
  return id;
}

async function getPayeeWalletAccountId(
  client: PoolClient,
  args: { organizationId: string; payeeUserId: string }
): Promise<string> {
  const { rows } = await client.query<{ id: string }>(
    `
    SELECT id::text AS id
    FROM public.wallet_accounts
    WHERE organization_id = $1::uuid
      AND user_id = $2::uuid
      AND is_platform_wallet = false
    ORDER BY created_at ASC
    LIMIT 1;
    `,
    [args.organizationId, args.payeeUserId]
  );

  const id = rows?.[0]?.id;
  if (!id) {
    const e: any = new Error("Payee wallet account not found");
    e.code = "PAYEE_WALLET_NOT_FOUND";
    throw e;
  }
  return id;
}

export async function debitPlatformFee(
  client: PoolClient,
  args: {
    organizationId: string;
    referenceType: string;
    referenceId: string;
    amount: number;
    currency: string;
    note?: string | null; // kept for compatibility; not required for insert
  }
): Promise<void> {
  const walletAccountId = await getPlatformWalletAccountId(
    client,
    args.organizationId
  );

  await insertWalletTransaction(client, {
    organizationId: args.organizationId,
    walletAccountId,
    txnType: "debit_platform_fee",
    amount: Number(args.amount),
    currency: args.currency,
    referenceType: args.referenceType,
    referenceId: args.referenceId,
  });
}

export async function debitPayee(
  client: PoolClient,
  args: {
    organizationId: string;
    payeeUserId: string;
    referenceType: string;
    referenceId: string;
    amount: number;
    currency: string;
    note?: string | null; // kept for compatibility; not required for insert
  }
): Promise<void> {
  const walletAccountId = await getPayeeWalletAccountId(client, {
    organizationId: args.organizationId,
    payeeUserId: args.payeeUserId,
  });

  await insertWalletTransaction(client, {
    organizationId: args.organizationId,
    walletAccountId,
    txnType: "debit_payee",
    amount: Number(args.amount),
    currency: args.currency,
    referenceType: args.referenceType,
    referenceId: args.referenceId,
  });
}
