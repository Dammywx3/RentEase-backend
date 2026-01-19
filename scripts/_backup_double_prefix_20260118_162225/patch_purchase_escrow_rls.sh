#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# RentEase Purchase/Escrow + RLS Guard Patch
# - Fix escrow delta-vs-total bugs
# - Strengthen RLS: refuse to run if context not set
# - Backup patched files
# ------------------------------------------------------------

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$ROOT/.patch_backups/$TS"
mkdir -p "$BACKUP_DIR"

say() { printf "\n\033[1m%s\033[0m\n" "$*"; }
ok() { printf "✅ %s\n" "$*"; }
warn() { printf "⚠️ %s\n" "$*"; }
die() { printf "❌ %s\n" "$*"; exit 1; }

need_file() {
  [[ -f "$1" ]] || die "Missing required file: $1"
}

backup() {
  local f="$1"
  local dest="$BACKUP_DIR/${f//\//__}"
  cp -a "$f" "$dest"
  ok "Backup: $f -> $dest"
}

# Safe python patch helper: requires a marker to be found or it aborts.
py_patch() {
  local file="$1"
  local marker="$2"
  local pycode="$3"

  backup "$file"

  python3 - "$file" "$marker" <<'PY' $pycode
import sys, pathlib, re

path = pathlib.Path(sys.argv[1])
marker = sys.argv[2]
src = path.read_text(encoding="utf-8")

if marker not in src:
    print(f"[ABORT] Marker not found in {path}: {marker}", file=sys.stderr)
    sys.exit(2)

# --- patch code injected via stdin argv tail ---
PY
  # Append actual code after the heredoc header:
}

# Because bash heredoc can’t easily pass dynamic python, we do a different pattern:
py_patch_inline() {
  local file="$1"
  local marker="$2"
  shift 2
  local code="$*"

  backup "$file"

  python3 - "$file" "$marker" <<PY
import sys, pathlib, re

path = pathlib.Path(sys.argv[1])
marker = sys.argv[2]
src = path.read_text(encoding="utf-8")

if marker not in src:
    raise SystemExit(f"[ABORT] Marker not found in {path}: {marker}")

orig = src

# ---- PATCH START ----
${code}
# ---- PATCH END ----

if src == orig:
    raise SystemExit(f"[ABORT] No changes applied to {path} (patch did nothing).")

path.write_text(src, encoding="utf-8")
print(f"[OK] Patched {path}")
PY
}

say "Patch target repo: $ROOT"
say "Backups will be stored in: $BACKUP_DIR"

# ------------------------------------------------------------
# 0) Ensure required files exist
# ------------------------------------------------------------
need_file "src/routes/purchases.routes.ts"
need_file "src/routes/purchase_close.ts"
need_file "src/routes/purchase_escrow.ts"
need_file "src/db/set_pg_context.ts" || warn "src/db/set_pg_context.ts not found (continuing, but RLS guard helper will still be created)"

# ------------------------------------------------------------
# 1) Create RLS Guard helper (NEW FILE)
#    - Ensures org/user context is set in the DB session
#    - Prevents “route forgot setPgContext” mistakes
# ------------------------------------------------------------
say "Creating: src/db/rls_guard.ts"
mkdir -p "src/db"

if [[ -f "src/db/rls_guard.ts" ]]; then
  backup "src/db/rls_guard.ts"
fi

cat > "src/db/rls_guard.ts" <<'EOF'
// src/db/rls_guard.ts
import type { PoolClient } from "pg";

/**
 * Super RLS Guard:
 * - Ensures the backend has set session context variables used by RLS:
 *   - app.organization_id / request.jwt.claim.* / etc (via current_organization_uuid())
 *   - app.user_id / app.current_user (via current_user_uuid())
 *
 * If context is missing, we throw BEFORE doing any writes.
 *
 * Call this AFTER setPgContext() and BEFORE business SQL.
 */
export async function assertRlsContext(client: PoolClient) {
  const { rows } = await client.query<{
    org_id: string | null;
    user_id: string | null;
  }>(`
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

  // user can be null for system/webhook flows, so only enforce user in authenticated routes
  return { orgId, userId };
}

/**
 * Enforce both org + user (normal authenticated API routes).
 */
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
ok "Created/updated src/db/rls_guard.ts"

# ------------------------------------------------------------
# 2) Patch purchases.routes.ts
#    - Fix escrow hold/release: DELTA -> NEW TOTAL
#    - Fix autoEscrow logic: pass totals
#    - Add RLS guard enforcement in routes
# ------------------------------------------------------------
say "Patching: src/routes/purchases.routes.ts"

py_patch_inline "src/routes/purchases.routes.ts" "purchase_escrow_hold" '
# Add import for RLS guard (idempotent)
if "assertRlsContextWithUser" not in src:
    src = src.replace(
        \'import { setPgContext } from "../db/set_pg_context.js";\',
        \'import { setPgContext } from "../db/set_pg_context.js";\\nimport { assertRlsContextWithUser } from "../db/rls_guard.js";\'
    )

# After each setPgContext(...) in this file, enforce RLS context for user routes.
# (conservative: only add if not already present)
def add_guard_after_setPgContext(block: str) -> str:
    if "await assertRlsContextWithUser" in block:
        return block
    return block + "\\n      await assertRlsContextWithUser(client);\\n"

# Patch occurrences in the file where we do: await setPgContext(client, { ... });
src = re.sub(
    r"(await setPgContext\\(client,\\s*\\{[\\s\\S]*?\\}\\);)",
    lambda m: add_guard_after_setPgContext(m.group(1)),
    src
)

# ---- Fix /:purchaseId/escrow/hold route: treat request.amount as DELTA and convert to NEW TOTAL
# Find the call array that currently uses amount directly.
src = src.replace(
    "[purchaseId, orgId, amount, purchase.currency, note ?? \"escrow hold\"]",
    "[purchaseId, orgId, newTotalHeld, purchase.currency, note ?? \"escrow hold\"]"
)

# Insert newTotalHeld calc near where amount/note exists (only if not present)
if "const newTotalHeld" not in src:
    src = src.replace(
        "const amount = Number(request.body.amount);\\n      const note = (request.body.note ?? null) as string | null;",
        "const amount = Number(request.body.amount);\\n      const note = (request.body.note ?? null) as string | null;\\n\\n      // Treat request.amount as DELTA, convert to NEW TOTAL for DB function\\n      // DB function purchase_escrow_hold expects NEW TOTAL held\\n      // newTotalHeld = currentHeld + delta\\n      // (we compute currentHeld after fetching purchase)\\n      let newTotalHeld = 0;"
    )

# After we fetch purchase, set newTotalHeld properly
src = src.replace(
    "const purchase = await fetchPurchaseOr404(client, purchaseId, orgId);",
    "const purchase = await fetchPurchaseOr404(client, purchaseId, orgId);\\n\\n        const currentHeld = Number(purchase?.escrow_held_amount ?? 0);\\n        newTotalHeld = currentHeld + amount;"
)

# ---- Fix /:purchaseId/escrow/release route: treat request.amount as DELTA and convert to NEW TOTAL
# Replace held check to compare against newTotalRelease (not delta)
src = src.replace(
    "if (held < amount) {",
    "const currentReleased = Number(purchase.escrow_released_amount ?? 0);\\n        const newTotalRelease = currentReleased + amount;\\n\\n        if (held < newTotalRelease) {"
)

# Replace function call array to use newTotalRelease
src = src.replace(
    "[purchaseId, orgId, amount, purchase.currency, platformFeeAmount, note ?? \"escrow release\"]",
    "[purchaseId, orgId, newTotalRelease, purchase.currency, platformFeeAmount, note ?? \"escrow release\"]"
)

# ---- Fix autoEscrow hold in /status route: pass TOTAL deposit (not delta)
src = src.replace(
    "const toHold = deposit - alreadyHeld;\\n              await client.query(\\n                `select public.purchase_escrow_hold($1::uuid, $2::uuid, $3::numeric, $4::text, $5::text);`,\\n                [purchaseId, orgId, toHold, refreshed.currency, note ?? \"auto escrow hold\"]\\n              );",
    "await client.query(\\n                `select public.purchase_escrow_hold($1::uuid, $2::uuid, $3::numeric, $4::text, $5::text);`,\\n                // DB function expects NEW TOTAL held\\n                [purchaseId, orgId, deposit, refreshed.currency, note ?? \"auto escrow hold\"]\\n              );"
)

# ---- Fix autoEscrow release on close: pass TOTAL held (not remaining delta)
src = src.replace(
    "const remaining = held - alreadyReleased;\\n              if (remaining > 0) {\\n                await client.query(\\n                  `select public.purchase_escrow_release($1::uuid, $2::uuid, $3::numeric, $4::text, $5::numeric, $6::text);`,\\n                  [purchaseId, orgId, remaining, refreshed.currency, platformFeeAmount, note ?? \"auto escrow release\"]\\n                );\\n              }",
    "if (held > alreadyReleased) {\\n                await client.query(\\n                  `select public.purchase_escrow_release($1::uuid, $2::uuid, $3::numeric, $4::text, $5::numeric, $6::text);`,\\n                  // DB function expects NEW TOTAL released\\n                  [purchaseId, orgId, held, refreshed.currency, platformFeeAmount, note ?? \"auto escrow release\"]\\n                );\\n              }"
)
'

ok "Patched purchases.routes.ts"

# ------------------------------------------------------------
# 3) Patch purchase_escrow.ts
#    - Fix actor id extraction (use req.user.id fallback)
#    - Use eventNote from body note (audit trail)
#    - Add RLS guard enforcement
# ------------------------------------------------------------
say "Patching: src/routes/purchase_escrow.ts"
py_patch_inline "src/routes/purchase_escrow.ts" "setPgContext" '
# Add import for RLS guard
if "assertRlsContextWithUser" not in src:
    src = src.replace(
        \'import { setPgContext } from "../db/set_pg_context.js";\',
        \'import { setPgContext } from "../db/set_pg_context.js";\\nimport { assertRlsContextWithUser } from "../db/rls_guard.js";\'
    )

# Fix userId extraction line
src = re.sub(
    r"const userId\\s*=\\s*String\\(\\(req as any\\)\\.user\\?\\.userId\\s*\\?\\?\\s*\"\"\\)\\.trim\\(\\);",
    "const userId = String((req as any).user?.id || (req as any).user?.userId || (req as any).userId || \"\").trim();",
    src
)

# Use eventNote from body note (or fallback)
src = src.replace(
    "eventNote: \"purchase_escrow\"",
    "eventNote: body?.note ?? \"purchase_escrow\""
)

# Ensure we assert RLS context after setPgContext
if "await assertRlsContextWithUser(client);" not in src:
    src = src.replace(
        "await setPgContext(client, { userId, organizationId, role: String(req.user?.role ?? \"\").trim() || null, eventNote: body?.note ?? \"purchase_escrow\" });",
        "await setPgContext(client, { userId, organizationId, role: String(req.user?.role ?? \"\").trim() || null, eventNote: body?.note ?? \"purchase_escrow\" });\n        await assertRlsContextWithUser(client);"
    )
'
ok "Patched purchase_escrow.ts"

# ------------------------------------------------------------
# 4) Patch purchase_close.ts
#    - Wrap in transaction + timezone + RLS guard
# ------------------------------------------------------------
say "Patching: src/routes/purchase_close.ts"
py_patch_inline "src/routes/purchase_close.ts" "purchase_close_complete" '
# Add import for RLS guard
if "assertRlsContextWithUser" not in src:
    src = src.replace(
        \'import { setPgContext } from "../db/set_pg_context.js";\',
        \'import { setPgContext } from "../db/set_pg_context.js";\\nimport { assertRlsContextWithUser } from "../db/rls_guard.js";\'
    )

# Add BEGIN/COMMIT and ROLLBACK in catch (only if not already present)
if \'await client.query("BEGIN");\' not in src:
    # Insert BEGIN/TZ right after try {
    src = src.replace(
        "try {",
        "try {\\n        await client.query(\\"BEGIN\\");\\n        await client.query(\\"SET LOCAL TIME ZONE \\'UTC\\'\\");"
    )

# After setPgContext(...) add guard
src = re.sub(
    r"(await setPgContext\\(client,\\s*\\{[\\s\\S]*?\\}\\);)",
    lambda m: m.group(1) + "\\n\\n        await assertRlsContextWithUser(client);",
    src
)

# Before successful return, COMMIT once.
# We place COMMIT right before: return reply.send(...)
if \'await client.query("COMMIT");\' not in src:
    src = src.replace(
        "return reply.send({ ok: true, data: result || { ok: true } });",
        "await client.query(\\"COMMIT\\");\\n\\n        return reply.send({ ok: true, data: result || { ok: true } });"
    )

# Ensure catch does rollback
if "await client.query(\"ROLLBACK\")" not in src:
    src = src.replace(
        "catch (e: any) {",
        "catch (e: any) {\\n        try { await client.query(\\"ROLLBACK\\"); } catch {}"
    )
'
ok "Patched purchase_close.ts"

# ------------------------------------------------------------
# 5) Quick sanity output
# ------------------------------------------------------------
say "Done. Showing git diff (if repo is git):"
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git diff --stat || true
  say "Tip: run: git diff   (to inspect exact changes)"
else
  warn "Not a git repo (skip git diff). You can inspect files manually."
fi

say "Backups saved in: $BACKUP_DIR"
ok "Patch complete. Your terminal will remain open."