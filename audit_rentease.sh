#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"

echo "============================================================"
echo "RentEase Backend Audit (codebase + db integration views)"
echo "Root: $ROOT"
echo "============================================================"
cd "$ROOT"

section () { echo; echo "==================== $* ===================="; }

# Basic context
section "1) Repo overview"
pwd
echo
echo "Node/TS config files:"
ls -1 2>/dev/null | grep -E '^(package\.json|tsconfig\.json|tsconfig\.build\.json|eslint|prettier|pnpm-lock|package-lock|yarn\.lock)$' || true
echo
echo "src tree (top-level):"
find src -maxdepth 2 -type d 2>/dev/null | sed 's#^\./##' | sort || true

# Key config (env + server bootstrap)
section "2) Entry points & server/bootstrap"
for f in src/index.ts src/server.ts src/app.ts src/main.ts src/routes/index.ts; do
  if [ -f "$f" ]; then
    echo
    echo "----- $f -----"
    sed -n '1,260p' "$f"
  fi
done

# JWT/auth plugin + middleware
section "3) Auth/JWT middleware + fastify decorations"
for f in src/plugins/jwt.ts src/middleware/auth.ts src/types/fastify.d.ts; do
  if [ -f "$f" ]; then
    echo
    echo "----- $f -----"
    sed -n '1,260p' "$f"
  fi
done

# Where authenticate is decorated/used
section "4) Where authenticate/optionalAuthenticate are referenced"
grep -RIn --exclude-dir=node_modules --exclude='*.bak*' -E \
  'decorate\((\"|\x27)authenticate|decorate\((\"|\x27)optionalAuthenticate|authenticate\]|\bauthenticate\b|\boptionalAuthenticate\b' \
  src | sed -n '1,220p' || true

# All routes, plus preHandlers
section "5) Routes list + all preHandler usage"
ls -1 src/routes 2>/dev/null || true
echo
grep -RIn --exclude-dir=node_modules --exclude='*.bak*' \
  -E 'app\.(get|post|patch|put|delete)\(|fastify\.(get|post|patch|put|delete)\(|preHandler:' \
  src/routes | sed -n '1,260p' || true

# Print key routes completely
section "6) Full route files (auth, rent_invoices, purchases, tenancies, payments/webhooks if any)"
ROUTE_FILES=(
  src/routes/auth.ts
  src/routes/rent_invoices.ts
  src/routes/purchases.routes.ts
  src/routes/tenancies.ts
  src/routes/applications.ts
  src/routes/listings.ts
  src/routes/properties.ts
  src/routes/viewings.ts
  src/routes/organizations.ts
  src/routes/me.ts
)
for f in "${ROUTE_FILES[@]}"; do
  if [ -f "$f" ]; then
    echo
    echo "----- $f -----"
    sed -n '1,340p' "$f"
  fi
done

# Services + repos involved in rent invoices, payments, ledger, paystack, webhooks
section "7) Services/Repos: rent invoices, payments, ledger, paystack/webhooks"
PATTERNS=(
  "rent_invoice"
  "rent_invoices"
  "invoice_payments"
  "payments"
  "payment_splits"
  "wallet_credit_from_splits"
  "creditPlatformFee"
  "creditPayee"
  "paystack"
  "webhook"
  "transaction_reference"
  "reference_type"
  "reference_id"
)
for p in "${PATTERNS[@]}"; do
  echo
  echo "---- matches for: $p ----"
  grep -RIn --exclude-dir=node_modules --exclude='*.bak*' "$p" src/services src/repos src/plugins src/routes src/db src/config 2>/dev/null | sed -n '1,220p' || true
done

# Dump full contents of likely key files if they exist
section "8) Full key service/repo files if present"
KEY_FILES=(
  src/services/rent_invoices.service.ts
  src/repos/rent_invoices.repo.ts
  src/services/ledger.service.ts
  src/services/payments.service.ts
  src/services/purchase_payments.service.ts
  src/plugins/paystack.ts
  src/routes/webhooks.ts
  src/routes/payments.ts
  src/config/payment.config.ts
  src/config/fees.config.ts
  src/db/set_pg_context.ts
)
for f in "${KEY_FILES[@]}"; do
  if [ -f "$f" ]; then
    echo
    echo "----- $f -----"
    sed -n '1,380p' "$f"
  fi
done

# Confirm whether routes read x-organization-id directly
section "9) Ensure routes do NOT read x-organization-id directly"
grep -RIn --exclude-dir=node_modules --exclude='*.bak*' -E \
  'headers\[[^]]*x-organization-id|req\.headers.*x-organization-id|x-organization-id["'"'"']' \
  src/routes || echo "✅ No routes read x-organization-id directly"

# DB migrations (if any)
section "10) Migrations overview (recent + contents)"
if [ -d migrations ]; then
  echo "migrations/:"
  ls -1 migrations | tail -n 50
  echo
  echo "Show last 3 migration files (first 260 lines each):"
  for f in $(ls -1 migrations 2>/dev/null | tail -n 3); do
    echo
    echo "----- migrations/$f -----"
    sed -n '1,260p' "migrations/$f"
  done
else
  echo "No migrations/ folder found."
fi

# Optional: DB schema snippets (only if local postgres + db exists)
section "11) OPTIONAL DB introspection (runs only if psql works)"
if command -v psql >/dev/null 2>&1; then
  if psql -d rentease -X -c "select 1" >/dev/null 2>&1; then
    echo "✅ Connected to db: rentease"
    echo
    echo "Tables:"
    psql -d rentease -X -P pager=off -c "
      select table_name
      from information_schema.tables
      where table_schema='public' and table_type='BASE TABLE'
      order by table_name;
    " | sed -n '1,260p'
    echo
    echo "payments table:"
    psql -d rentease -X -P pager=off -c "\d+ public.payments" | sed -n '1,260p'
    echo
    echo "rent_invoices table:"
    psql -d rentease -X -P pager=off -c "\d+ public.rent_invoices" | sed -n '1,260p'
    echo
    echo "invoice_payments table:"
    psql -d rentease -X -P pager=off -c "\d+ public.invoice_payments" | sed -n '1,220p'
    echo
    echo "validate_payment_matches_listing() source:"
    psql -d rentease -X -P pager=off -c "\sf+ public.validate_payment_matches_listing" | sed -n '1,260p'
    echo
    echo "payments_success_trigger_fn() source:"
    psql -d rentease -X -P pager=off -c "\sf+ public.payments_success_trigger_fn" | sed -n '1,120p'
  else
    echo "psql exists but cannot connect to db 'rentease' (skipping DB section)."
  fi
else
  echo "psql not installed (skipping DB section)."
fi

section "DONE"
