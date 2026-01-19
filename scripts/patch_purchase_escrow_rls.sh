#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$ROOT/.patch_backups/$TS"
mkdir -p "$BACKUP_DIR"

say() { printf "\n\033[1m%s\033[0m\n" "$*"; }
ok()  { printf "✅ %s\n" "$*"; }
warn(){ printf "⚠️ %s\n" "$*"; }
die() { printf "❌ %s\n" "$*"; exit 1; }

need_file() { [[ -f "$1" ]] || die "Missing required file: $1"; }
backup() {
  local f="$1"
  local dest="$BACKUP_DIR/${f//\//__}"
  cp -a "$f" "$dest"
  ok "Backup: $f -> $dest"
}

say "Patch target repo: $ROOT"
say "Backups: $BACKUP_DIR"

need_file "src/routes/purchases.routes.ts"
need_file "src/routes/purchase_close.ts"
need_file "src/routes/purchase_escrow.ts"
[[ -f "src/db/set_pg_context.ts" ]] || warn "src/db/set_pg_context.ts not found (ok if you use .js import paths)"

# ------------------------------------------------------------
# 1) Create/refresh rls_guard.ts
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
# 2) Patch purchases.routes.ts (delta -> total + guard)
# ------------------------------------------------------------
say "Patching: src/routes/purchases.routes.ts"
backup "src/routes/purchases.routes.ts"

python3 - <<'PY'
import pathlib, re

p = pathlib.Path("src/routes/purchases.routes.ts")
src = p.read_text(encoding="utf-8")

if "purchase_escrow_hold" not in src:
    raise SystemExit("[ABORT] purchases.routes.ts: marker 'purchase_escrow_hold' not found")

# Add import
if "assertRlsContextWithUser" not in src:
    src = src.replace(
        'import { setPgContext } from "../db/set_pg_context.js";',
        'import { setPgContext } from "../db/set_pg_context.js";\nimport { assertRlsContextWithUser } from "../db/rls_guard.js";'
    )

# After every setPgContext(...) add guard (idempotent)
def add_guard(m):
    block = m.group(0)
    if "assertRlsContextWithUser" in block:
        return block
    return block + "\n      await assertRlsContextWithUser(client);\n"

src = re.sub(r'await setPgContext\([\s\S]*?\);\s*', add_guard, src)

# HOLD: replace function args amount -> newTotalHeld (only if pattern exists)
src = src.replace(
    "[purchaseId, orgId, amount, purchase.currency, note ?? \"escrow hold\"]",
    "[purchaseId, orgId, newTotalHeld, purchase.currency, note ?? \"escrow hold\"]"
)

# Ensure newTotalHeld exists
if "let newTotalHeld = 0" not in src:
    src = src.replace(
        "const amount = Number(request.body.amount);\n      const note = (request.body.note ?? null) as string | null;",
        "const amount = Number(request.body.amount);\n      const note = (request.body.note ?? null) as string | null;\n\n      // Treat request.amount as DELTA, convert to NEW TOTAL for DB function\n      let newTotalHeld = 0;"
    )

# After purchase fetch, compute total held
src = src.replace(
    "const purchase = await fetchPurchaseOr404(client, purchaseId, orgId);",
    "const purchase = await fetchPurchaseOr404(client, purchaseId, orgId);\n\n        const currentHeld = Number((purchase as any)?.escrow_held_amount ?? 0);\n        newTotalHeld = currentHeld + amount;"
)

# RELEASE: delta -> total released
src = src.replace(
    "if (held < amount) {",
    "const currentReleased = Number((purchase as any).escrow_released_amount ?? 0);\n        const newTotalRelease = currentReleased + amount;\n\n        if (held < newTotalRelease) {"
)

src = src.replace(
    "[purchaseId, orgId, amount, purchase.currency, platformFeeAmount, note ?? \"escrow release\"]",
    "[purchaseId, orgId, newTotalRelease, purchase.currency, platformFeeAmount, note ?? \"escrow release\"]"
)

# Auto hold: pass TOTAL deposit
src = src.replace(
    "const toHold = deposit - alreadyHeld;\n              await client.query(\n                `select public.purchase_escrow_hold($1::uuid, $2::uuid, $3::numeric, $4::text, $5::text);`,\n                [purchaseId, orgId, toHold, refreshed.currency, note ?? \"auto escrow hold\"]\n              );",
    "await client.query(\n                `select public.purchase_escrow_hold($1::uuid, $2::uuid, $3::numeric, $4::text, $5::text);`,\n                // DB function expects NEW TOTAL held\n                [purchaseId, orgId, deposit, refreshed.currency, note ?? \"auto escrow hold\"]\n              );"
)

# Auto release: pass TOTAL held
src = src.replace(
    "const remaining = held - alreadyReleased;\n              if (remaining > 0) {\n                await client.query(\n                  `select public.purchase_escrow_release($1::uuid, $2::uuid, $3::numeric, $4::text, $5::numeric, $6::text);`,\n                  [purchaseId, orgId, remaining, refreshed.currency, platformFeeAmount, note ?? \"auto escrow release\"]\n                );\n              }",
    "if (held > alreadyReleased) {\n                await client.query(\n                  `select public.purchase_escrow_release($1::uuid, $2::uuid, $3::numeric, $4::text, $5::numeric, $6::text);`,\n                  // DB function expects NEW TOTAL released\n                  [purchaseId, orgId, held, refreshed.currency, platformFeeAmount, note ?? \"auto escrow release\"]\n                );\n              }"
)

p.write_text(src, encoding="utf-8")
print("[OK] Patched src/routes/purchases.routes.ts")
PY

ok "Patched purchases.routes.ts"

# ------------------------------------------------------------
# 3) Patch purchase_escrow.ts (user id + guard)
# ------------------------------------------------------------
say "Patching: src/routes/purchase_escrow.ts"
backup "src/routes/purchase_escrow.ts"

python3 - <<'PY'
import pathlib, re

p = pathlib.Path("src/routes/purchase_escrow.ts")
src = p.read_text(encoding="utf-8")

if "setPgContext" not in src:
    raise SystemExit("[ABORT] purchase_escrow.ts: marker 'setPgContext' not found")

if "assertRlsContextWithUser" not in src:
    src = src.replace(
        'import { setPgContext } from "../db/set_pg_context.js";',
        'import { setPgContext } from "../db/set_pg_context.js";\nimport { assertRlsContextWithUser } from "../db/rls_guard.js";'
    )

# Robust userId extraction (only if old pattern exists)
src = re.sub(
    r'const userId\s*=\s*String\(\(req as any\)\.user\?\.(?:userId)\s*\?\?\s*""\)\.trim\(\);',
    'const userId = String((req as any).user?.id || (req as any).user?.userId || (req as any).userId || "").trim();',
    src
)

# Ensure we assert after setPgContext
if "await assertRlsContextWithUser(client);" not in src:
    src = re.sub(
        r'(await setPgContext\([\s\S]*?\);\s*)',
        r'\1        await assertRlsContextWithUser(client);\n',
        src,
        count=1
    )

p.write_text(src, encoding="utf-8")
print("[OK] Patched src/routes/purchase_escrow.ts")
PY

ok "Patched purchase_escrow.ts"

# ------------------------------------------------------------
# 4) Patch purchase_close.ts (tx + guard)
# ------------------------------------------------------------
say "Patching: src/routes/purchase_close.ts"
backup "src/routes/purchase_close.ts"

python3 - <<'PY'
import pathlib, re

p = pathlib.Path("src/routes/purchase_close.ts")
src = p.read_text(encoding="utf-8")

if "purchase_close_complete" not in src:
    raise SystemExit("[ABORT] purchase_close.ts: marker 'purchase_close_complete' not found")

if "assertRlsContextWithUser" not in src:
    src = src.replace(
        'import { setPgContext } from "../db/set_pg_context.js";',
        'import { setPgContext } from "../db/set_pg_context.js";\nimport { assertRlsContextWithUser } from "../db/rls_guard.js";'
    )

# Insert BEGIN/TZ after try { if missing
if 'await client.query("BEGIN");' not in src:
    src = src.replace(
        "try {",
        "try {\n        await client.query(\"BEGIN\");\n        await client.query(\"SET LOCAL TIME ZONE 'UTC'\");"
    )

# Add guard after any setPgContext
src = re.sub(
    r'(await setPgContext\([\s\S]*?\);\s*)',
    r'\1\n        await assertRlsContextWithUser(client);\n',
    src
)

# Ensure rollback in catch
if 'await client.query("ROLLBACK")' not in src:
    src = src.replace(
        "catch (e: any) {",
        "catch (e: any) {\n        try { await client.query(\"ROLLBACK\"); } catch {}"
    )

# Ensure commit before return success (best-effort: common pattern)
if 'await client.query("COMMIT");' not in src and "return reply.send({ ok: true" in src:
    src = src.replace(
        "return reply.send({ ok: true, data: result || { ok: true } });",
        "await client.query(\"COMMIT\");\n\n        return reply.send({ ok: true, data: result || { ok: true } });"
    )

p.write_text(src, encoding="utf-8")
print("[OK] Patched src/routes/purchase_close.ts")
PY

ok "Patched purchase_close.ts"

# ------------------------------------------------------------
# 5) Report
# ------------------------------------------------------------
say "Done."
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git diff --stat || true
  say "Run: git diff"
fi
ok "Backups saved in: $BACKUP_DIR"
