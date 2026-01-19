#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$ROOT/.patch_backups/$TS"
mkdir -p "$BACKUP_DIR"

say() { printf "\n\033[1m%s\033[0m\n" "$*"; }
ok()  { printf "✅ %s\n" "$*"; }
die() { printf "❌ %s\n" "$*"; exit 1; }

need_file() { [[ -f "$1" ]] || die "Missing file: $1"; }
backup() {
  local f="$1"
  local dest="$BACKUP_DIR/${f//\//__}"
  cp -a "$f" "$dest"
  ok "Backup: $f -> $dest"
}

say "Repo: $ROOT"
say "Backups: $BACKUP_DIR"

need_file "src/services/paystack_finalize.service.ts"
need_file "src/routes/payments.ts"

# ------------------------------------------------------------
# 1) Ensure RLS guard exists
# ------------------------------------------------------------
say "Ensuring: src/db/rls_guard.ts"
mkdir -p "src/db"
if [[ -f "src/db/rls_guard.ts" ]]; then backup "src/db/rls_guard.ts"; fi

cat > "src/db/rls_guard.ts" <<'EOF'
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
EOF
ok "Wrote src/db/rls_guard.ts"

# ------------------------------------------------------------
# 2) Patch payments.ts
# ------------------------------------------------------------
say "Patching: src/routes/payments.ts"
backup "src/routes/payments.ts"

python3 - <<'PY'
import pathlib, re, sys

p = pathlib.Path("src/routes/payments.ts")
src = p.read_text(encoding="utf-8")

if "setPgContext" not in src:
    raise SystemExit("[ABORT] payments.ts: marker 'setPgContext' not found")

# Add import
if "assertRlsContextWithUser" not in src:
    src = src.replace(
        'import { setPgContext } from "../db/set_pg_context.js";',
        'import { setPgContext } from "../db/set_pg_context.js";\nimport { assertRlsContextWithUser } from "../db/rls_guard.js";'
    )

# Make userId extraction robust (covers req.user.id / req.user.userId / req.userId)
src = re.sub(
    r'const userId\s*=\s*String\(\(req as any\)\.user\?\.(?:userId)\s*\?\?\s*""\)\.trim\(\);',
    'const userId = String((req as any).user?.id || (req as any).user?.userId || (req as any).userId || "").trim();',
    src
)
src = re.sub(
    r'const userId\s*=\s*String\(\(req as any\)\.userId\s*\?\?\s*""\)\.trim\(\);',
    'const userId = String((req as any).user?.id || (req as any).user?.userId || (req as any).userId || "").trim();',
    src
)

# After every setPgContext(...) call, add assert (idempotent)
def add_guard(m):
    block = m.group(0)
    if "assertRlsContextWithUser" in block:
        return block
    return block + "\n        await assertRlsContextWithUser(client);\n"

src = re.sub(r'await setPgContext\([\s\S]*?\);\s*', add_guard, src)

p.write_text(src, encoding="utf-8")
print("[OK] Patched src/routes/payments.ts")
PY

ok "Patched payments.ts"

# ------------------------------------------------------------
# 3) Patch paystack_finalize.service.ts
# ------------------------------------------------------------
say "Patching: src/services/paystack_finalize.service.ts"
backup "src/services/paystack_finalize.service.ts"

python3 - <<'PY'
import pathlib, re

p = pathlib.Path("src/services/paystack_finalize.service.ts")
src = p.read_text(encoding="utf-8")

if "finalizePaystackChargeSuccess" not in src:
    raise SystemExit("[ABORT] paystack_finalize.service.ts: marker not found")

# Ensure RLS guard import exists
if "assertRlsContext" not in src:
    src = src.replace(
        'import { setPgContext } from "../db/set_pg_context.js";',
        'import { setPgContext } from "../db/set_pg_context.js";\nimport { assertRlsContext } from "../db/rls_guard.js";'
    )

# Ensure we assert org context after ensureOrgContextMatchesPayment(...)
if "Ensure org RLS context is set" not in src:
    src = src.replace(
        "await ensureOrgContextMatchesPayment(client, payment.organization_id);",
        "await ensureOrgContextMatchesPayment(client, payment.organization_id);\n\n  // Ensure org RLS context is set (webhook may have no user)\n  await assertRlsContext(client);"
    )

# Add helper finalizePurchaseEscrowFunding once (insert near approxEqual)
if "async function finalizePurchaseEscrowFunding" not in src:
    marker = "function approxEqual"
    helper = r'''async function finalizePurchaseEscrowFunding(client: PoolClient, args: {
  organizationId: string;
  purchaseId: string;
  amountMajor: number;
  currency: string;
  paymentId: string;
  note?: string | null;
}): Promise<{ ok: true } | { ok: false; error: string; message?: string }> {
  const { rows } = await client.query<{
    agreed_price: string;
    escrow_held_amount: string | null;
    payment_status: string | null;
  }>(
    `
    select
      agreed_price::text as agreed_price,
      escrow_held_amount::text as escrow_held_amount,
      payment_status::text as payment_status
    from public.property_purchases
    where id = $1::uuid
      and organization_id = $2::uuid
      and deleted_at is null
    limit 1
    for update;
    `,
    [args.purchaseId, args.organizationId]
  );

  const pr = rows?.[0];
  if (!pr) return { ok: false, error: "PURCHASE_NOT_FOUND" };

  const agreed = Number(pr.agreed_price);
  const curHeld = Number(pr.escrow_held_amount ?? "0");
  const nextHeld = curHeld + Number(args.amountMajor);

  if (!Number.isFinite(agreed) || agreed <= 0) return { ok: false, error: "INVALID_PURCHASE_PRICE" };
  if (!Number.isFinite(nextHeld) || nextHeld <= 0) return { ok: false, error: "INVALID_ESCROW_AMOUNT" };
  if (nextHeld > agreed) {
    return { ok: false, error: "ESCROW_OVERFUND_BLOCKED", message: `nextHeld=${nextHeld} > agreed=${agreed}` };
  }

  // DB function expects NEW TOTAL held
  await client.query(
    `select public.purchase_escrow_hold($1::uuid, $2::uuid, $3::numeric, $4::text, $5::text);`,
    [args.purchaseId, args.organizationId, nextHeld, args.currency, args.note ?? "paystack purchase escrow hold"]
  );

  await client.query(
    `
    update public.property_purchases
    set
      paid_at = coalesce(paid_at, now()),
      paid_amount = least(coalesce(paid_amount, 0) + $1::numeric, agreed_price),
      payment_status = case
        when (coalesce(paid_amount, 0) + $1::numeric) >= agreed_price then 'paid'::purchase_payment_status
        when (coalesce(paid_amount, 0) + $1::numeric) > 0 then 'partially_paid'::purchase_payment_status
        else payment_status
      end,
      last_payment_id = coalesce(last_payment_id, $2::uuid),
      updated_at = now()
    where id = $3::uuid
      and organization_id = $4::uuid
      and deleted_at is null;
    `,
    [args.amountMajor, args.paymentId, args.purchaseId, args.organizationId]
  );

  return { ok: true };
}

'''
    src = src.replace(marker, helper + marker)

# Add PURCHASE branch after `const orgId = payment.organization_id;`
if "PURCHASE PAYMENT RULE" not in src:
    src = re.sub(
        r'(const orgId\s*=\s*payment\.organization_id;\s*)',
        r'''\1
  // ------------------------------------------------------------
  // PURCHASE PAYMENT RULE:
  // For property purchases, do NOT pay seller/platform on webhook.
  // Instead: mark payment successful + fund escrow (hold).
  // Seller is paid only when escrow is released (closing).
  // Platform fee is taken during escrow release.
  // ------------------------------------------------------------
  if (payment.reference_type === "purchase" && payment.reference_id) {
    await client.query(
      `
      update public.payments
      set
        status = 'successful'::public.payment_status,
        completed_at = now(),
        gateway_transaction_id = coalesce(gateway_transaction_id, $2::text),
        gateway_response = coalesce(gateway_response, $3::jsonb),
        currency = coalesce(currency, $4::text),
        updated_at = now()
      where id = $1::uuid
        and organization_id = $5::uuid
        and deleted_at is null;
      `,
      [payment.id, String(evt.data?.id ?? ""), JSON.stringify(evt), currency, orgId]
    );

    const resEscrow = await finalizePurchaseEscrowFunding(client, {
      organizationId: orgId,
      purchaseId: payment.reference_id,
      amountMajor,
      currency,
      paymentId: payment.id,
      note: `paystack:charge.success:${reference}`,
    });

    if (!resEscrow.ok) return resEscrow;
    return { ok: true };
  }

''',
        src,
        count=1
    )

p.write_text(src, encoding="utf-8")
print("[OK] Patched src/services/paystack_finalize.service.ts")
PY

ok "Patched paystack_finalize.service.ts"

say "DONE ✅"
say "If git repo: run: git diff --stat && git diff"
ok "Backups saved at: $BACKUP_DIR"
