#!/usr/bin/env bash
set -u

ts="$(date +%s)"
backup() {
  local f="$1"
  if [ -f "$f" ]; then
    cp "$f" "$f.bak.$ts"
    echo "==> Backed up $f -> $f.bak.$ts"
  fi
}

ensure_dir() {
  mkdir -p "$1"
}

echo "==> Applying RLS TX full fix (Option A: BEGIN + SET LOCAL + setPgContext LOCAL)..."

# -------------------------------------------------------------------
# 1) Create: src/db/rls_tx.ts (canonical helper)
# -------------------------------------------------------------------
ensure_dir "src/db"
backup "src/db/rls_tx.ts"

cat > src/db/rls_tx.ts <<'EOF'
// src/db/rls_tx.ts
import type { PoolClient } from "pg";
import { withTransaction } from "../config/database.js";
import { setPgContext, type PgContextOpts } from "./set_pg_context.js";

export type RlsContext = {
  userId: string;
  organizationId: string;
  role?: string | null;
  eventNote?: string | null;
};

/**
 * ✅ Option A (Recommended for Pool):
 * - BEGIN (per-connection)
 * - SET LOCAL settings (LOCAL=true in set_config)
 * - run queries
 * - COMMIT/ROLLBACK
 *
 * Why: prevents RLS context leaking to the next request on the same pooled connection.
 */
export async function withRlsTransaction<T>(
  ctx: RlsContext,
  fn: (client: PoolClient) => Promise<T>
): Promise<T> {
  if (!ctx?.userId) throw new Error("withRlsTransaction missing userId");
  if (!ctx?.organizationId) throw new Error("withRlsTransaction missing organizationId");

  return withTransaction(async (client) => {
    // ✅ Force UTC for this transaction
    await client.query("SET LOCAL TIME ZONE 'UTC'");

    const opts: PgContextOpts = {
      userId: ctx.userId,
      organizationId: ctx.organizationId,
      role: ctx.role ?? null,
      eventNote: ctx.eventNote ?? null,
    };

    // ✅ sets BOTH: app.current_user/app.user_id AND app.organization_id/app.current_organization
    // ✅ uses LOCAL=true (scoped to current TX)
    await setPgContext(client, opts);

    return fn(client);
  });
}
EOF

echo "✅ Wrote: src/db/rls_tx.ts"

# -------------------------------------------------------------------
# 2) Patch: src/config/database.ts
#    - Ensure it imports setPgContext
#    - Replace its withRlsTransaction() to use setPgContext + correct keys
# -------------------------------------------------------------------
DBFILE="src/config/database.ts"
if [ -f "$DBFILE" ]; then
  backup "$DBFILE"

  # Ensure import exists (only add if missing)
  if ! grep -q "setPgContext" "$DBFILE"; then
    # Insert after env import if possible, else at top
    if grep -q "from \"./env\\.js\";" "$DBFILE"; then
      perl -0777 -i -pe 's/(from "\.\/env\.js";\s*\n)/$1import { setPgContext } from "..\/db\/set_pg_context.js";\n/s' "$DBFILE"
    else
      perl -0777 -i -pe 's/^/import { setPgContext } from "..\/db\/set_pg_context.js";\n/s' "$DBFILE"
    fi
  fi

  # Replace existing withRlsTransaction function (if present)
  if grep -q "export async function withRlsTransaction" "$DBFILE"; then
    perl -0777 -i -pe 's/export\s+async\s+function\s+withRlsTransaction<[^>]*>\s*\([\s\S]*?\)\s*:\s*Promise<[\s\S]*?>\s*\{[\s\S]*?\n\}/export async function withRlsTransaction<T>(\n  ctx: RlsContext,\n  fn: (client: PoolClient) => Promise<T>\n): Promise<T> {\n  if (!ctx.userId) throw new Error(\"withRlsTransaction missing userId\");\n  if (!ctx.organizationId) throw new Error(\"withRlsTransaction missing organizationId\");\n\n  return withTransaction(async (client) => {\n    // ✅ Force UTC for this transaction\/connection\n    await client.query(\"SET LOCAL TIME ZONE \\'UTC\\'\");\n\n    // ✅ Correct keys + LOCAL scoping\n    await setPgContext(client, {\n      userId: ctx.userId,\n      organizationId: ctx.organizationId,\n    });\n\n    return fn(client);\n  });\n}/s' "$DBFILE"
  fi

  echo "✅ Patched: $DBFILE"
else
  echo "⚠️ Not found: $DBFILE (skipping patch)"
fi

# -------------------------------------------------------------------
# 3) Ensure: src/db.ts exists and re-exports withRlsTransaction
#    (so old imports like `../db.js` keep working)
# -------------------------------------------------------------------
backup "src/db.ts"

if [ ! -f "src/db.ts" ]; then
  cat > src/db.ts <<'EOF'
// src/db.ts
export { withRlsTransaction } from "./db/rls_tx.js";
export type { RlsContext } from "./db/rls_tx.js";
EOF
  echo "✅ Created: src/db.ts"
else
  # Append exports only if missing
  if ! grep -q "withRlsTransaction" src/db.ts; then
    cat >> src/db.ts <<'EOF'

export { withRlsTransaction } from "./db/rls_tx.js";
export type { RlsContext } from "./db/rls_tx.js";
EOF
    echo "✅ Updated: src/db.ts (added exports)"
  else
    echo "✅ src/db.ts already exports withRlsTransaction"
  fi
fi

echo ""
echo "==> Next steps (run these):"
echo "  npm run build"
echo "  npm run dev"
echo ""
echo "==> Optional check:"
echo "  grep -RIn \"withRlsTransaction\" src/routes | head -n 50"
echo ""
echo "✅ Done."
