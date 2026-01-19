#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

stamp="$(date +%Y%m%d_%H%M%S)"
mkdir -p scripts/.bak

backup() {
  local f="$1"
  if [[ -f "$f" ]]; then
    cp "$f" "scripts/.bak/$(basename "$f").bak.$stamp"
    echo "✅ backup -> scripts/.bak/$(basename "$f").bak.$stamp"
  fi
}

echo "== Writing config + ledger =="

# -------------------------
# fees.config.ts
# -------------------------
backup "src/config/fees.config.ts"
cat > src/config/fees.config.ts <<'TS'
export type PaymentKind = "rent" | "buy" | "subscription";

export type FeeContext = {
  paymentKind: PaymentKind;
  amount: number;     // total paid amount
  currency: string;   // e.g. "USD" or "NGN"
};

export type FeeSplit = {
  platformFee: number; // >= 0
  payeeNet: number;    // >= 0
  pctUsed: number;
};

/**
 * SINGLE SOURCE OF TRUTH
 * Change these values in one place only.
 */
export const FEES = {
  platformFeePct: 2.5,
  minPlatformFee: 0,
  maxPlatformFee: Number.POSITIVE_INFINITY,
} as const;

export function round2(n: number): number {
  // Safe for numeric(15,2)
  return Math.round(n * 100) / 100;
}

export function computePlatformFeeSplit(ctx: FeeContext): FeeSplit {
  const pct = FEES.platformFeePct;

  let fee = round2((ctx.amount * pct) / 100);
  if (fee < FEES.minPlatformFee) fee = FEES.minPlatformFee;
  if (fee > FEES.maxPlatformFee) fee = FEES.maxPlatformFee;

  const net = round2(ctx.amount - fee);

  return {
    platformFee: fee,
    payeeNet: net,
    pctUsed: pct,
  };
}
TS
echo "✅ wrote: src/config/fees.config.ts"

# -------------------------
# plans.config.ts
# -------------------------
backup "src/config/plans.config.ts"
cat > src/config/plans.config.ts <<'TS'
export type PlanId = "free" | "premium";
export type BillingCycle = "monthly" | "yearly";

export const PLANS = {
  free: {
    id: "free" as const,
    monthlyPriceNGN: 0,
    access: "limited",
  },
  premium: {
    id: "premium" as const,
    monthlyPriceNGN: 15000,
    yearlyDiscountPct: 10, // 10% off annual
    access: "full",
  },
} as const;

export function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

/**
 * Returns how much user should pay for the plan.
 * - premium monthly: 15000 NGN
 * - premium yearly: 12 * 15000 minus 10%
 */
export function computePlanPriceNGN(planId: PlanId, cycle: BillingCycle): number {
  if (planId === "free") return 0;

  const monthly = PLANS.premium.monthlyPriceNGN;

  if (cycle === "monthly") return monthly;

  const yearBase = monthly * 12;
  const discount = (PLANS.premium.yearlyDiscountPct / 100) * yearBase;
  return round2(yearBase - discount);
}
TS
echo "✅ wrote: src/config/plans.config.ts"

# -------------------------
# ledger.service.ts
# -------------------------
backup "src/services/ledger.service.ts"
cat > src/services/ledger.service.ts <<'TS'
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
TS
echo "✅ wrote: src/services/ledger.service.ts"

echo ""
echo "== Patching rent_invoices.service.ts =="

SVC="src/services/rent_invoices.service.ts"
if [[ ! -f "$SVC" ]]; then
  echo "❌ missing file: $SVC"
  exit 1
fi

backup "$SVC"

python3 - <<'PY'
from pathlib import Path
import re

svc = Path("src/services/rent_invoices.service.ts")
txt = svc.read_text(encoding="utf-8")

# 1) Ensure imports exist: computePlatformFeeSplit + ledger functions
if "computePlatformFeeSplit" not in txt:
  # add after ensureWalletAccount import line
  txt = re.sub(
    r"(import\s+\{\s*ensureWalletAccount\s*\}\s+from\s+\"../utils/wallets\.js\";\s*)",
    r"\1import { computePlatformFeeSplit } from \"../config/fees.config.ts\";\n"
    r"import { creditPayee, creditPlatformFee } from \"../services/ledger.service.ts\";\n",
    txt,
    count=1
  )
else:
  # still ensure ledger import exists
  if "creditPlatformFee" not in txt or "creditPayee" not in txt:
    txt = re.sub(
      r"(import\s+\{\s*ensureWalletAccount\s*\}\s+from\s+\"../utils/wallets\.js\";\s*)",
      r"\1import { creditPayee, creditPlatformFee } from \"../services/ledger.service.ts\";\n",
      txt,
      count=1
    )

# 2) Replace the wallet credit block inside payRentInvoice:
# Find where payeeUserId resolved, payeeWalletId ensured, and INSERT into wallet_transactions happens.
# We'll replace from comment "// 4) Credit" up to just before "// 5) Mark invoice paid"
m = re.search(r"(\n\s*//\s*4\)\s*.*?\n)([\s\S]*?)(\n\s*//\s*5\)\s*Mark invoice paid)", txt)
if not m:
  raise SystemExit("ERROR: Could not find section markers '// 4)' and '// 5)' inside payRentInvoice. Paste your current file section around steps 4-5.")

before = txt[:m.start(2)]
after = txt[m.end(2):]

replacement = r"""
  // 4) Split platform fee (2.5%) + credit wallets (SINGLE SOURCE OF TRUTH)
  const split = computePlatformFeeSplit({
    paymentKind: "rent",
    amount,
    currency,
  });

  // Resolve payee (landlord/owner) and credit net
  const payeeUserId = await resolveRentInvoicePayeeUserId(
    client,
    invoice.id,
    invoice.organization_id
  );

  await creditPayee(client, {
    organizationId: invoice.organization_id,
    payeeUserId,
    referenceType: "rent_invoice",
    referenceId: invoice.id,
    amount: split.payeeNet,
    currency,
    note: `Rent net (after ${split.pctUsed}% fee) for invoice ${invoice.invoice_number ?? invoice.id}`,
  });

  // Credit platform fee into platform wallet
  await creditPlatformFee(client, {
    organizationId: invoice.organization_id,
    referenceType: "rent_invoice",
    referenceId: invoice.id,
    amount: split.platformFee,
    currency,
    note: `Platform fee (${split.pctUsed}%) for invoice ${invoice.invoice_number ?? invoice.id}`,
  });
"""

txt2 = before + replacement + after

svc.write_text(txt2, encoding="utf-8")
print("✅ patched rent_invoices.service.ts: removed embedded fee math + uses fees.config + ledger.service")
PY

echo ""
echo "== DONE =="
echo "✅ WROTE:"
echo "  - src/config/fees.config.ts"
echo "  - src/config/plans.config.ts"
echo "  - src/services/ledger.service.ts"
echo "✅ PATCHED:"
echo "  - src/services/rent_invoices.service.ts"
echo ""
echo "NEXT:"
echo "  1) Restart server: npm run dev"
echo "  2) Generate + pay a NEW invoice"
echo "  3) Verify BOTH txns exist:"
echo "     - credit_platform_fee (platform wallet)"
echo "     - credit_payee (landlord wallet)"
echo ""
echo "VERIFY SQL:"
echo "PAGER=cat psql -d \"\$DB_NAME\" -c \"select wt.txn_type, wt.amount, wa.user_id, wa.is_platform_wallet from public.wallet_transactions wt join public.wallet_accounts wa on wa.id=wt.wallet_account_id where wt.reference_type='rent_invoice' and wt.reference_id='\$INVOICE_ID'::uuid order by wt.created_at asc;\""
