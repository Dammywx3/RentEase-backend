#!/usr/bin/env bash
set -euo pipefail

STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="scripts/_backup_fix_remaining_routes_${STAMP}"
mkdir -p "$BACKUP_DIR"

backup() {
  local f="$1"
  [ -f "$f" ] || return 0
  cp "$f" "$BACKUP_DIR/$(basename "$f")"
}

echo "============================================================"
echo "Fix remaining routes (debug_pgctx import + duplicate GET / + broken listings quote)"
echo "Backup: $BACKUP_DIR"
echo "============================================================"

# ------------------------------------------------------------
# 0) Ensure debug_pgctx.ts exists and create shim debug_pgctx.js
#    This fixes: ERR_MODULE_NOT_FOUND for debug_pgctx.js during tsx watch
# ------------------------------------------------------------
backup "src/routes/index.ts"
backup "src/routes/debug_pgctx.ts"
backup "src/routes/debug_pgctx.js"

mkdir -p src/routes

if [ ! -f "src/routes/debug_pgctx.ts" ]; then
  cat > src/routes/debug_pgctx.ts <<'TS'
import type { FastifyInstance } from "fastify";
import type { PoolClient } from "pg";
import { withRlsTransaction } from "../db/rls_tx.js";

export async function debugPgCtxRoutes(app: FastifyInstance) {
  app.get("/debug/pgctx", { preHandler: [app.authenticate] }, async (req: any) => {
    const data = await withRlsTransaction(
      {
        userId: String(req?.user?.userId ?? req?.user?.sub ?? "").trim(),
        organizationId: String(req?.orgId ?? "").trim(),
        role: (req?.user?.role ?? null) as any,
        eventNote: "debug:pgctx",
      },
      async (client: PoolClient) => {
        const { rows } = await client.query(`
          select
            current_setting('app.organization_id', true) as org_id,
            current_setting('app.user_id', true) as user_id,
            current_setting('rentease.user_role', true) as role,
            current_setting('app.event_note', true) as event_note,
            current_setting('request.header.x_organization_id', true) as hdr_org,
            current_setting('request.jwt.claim.sub', true) as jwt_sub
        `);
        return rows?.[0] ?? null;
      }
    );
    return { ok: true, data };
  });
}
TS
  echo "✅ created src/routes/debug_pgctx.ts"
else
  echo "✅ src/routes/debug_pgctx.ts already exists"
fi

# Shim JS file so runtime import works even when tsx doesn’t map .js -> .ts
cat > src/routes/debug_pgctx.js <<'JS'
export * from "./debug_pgctx.ts";
JS
echo "✅ wrote shim src/routes/debug_pgctx.js"

# Ensure index.ts imports and registers debugPgCtxRoutes (root-level, not /v1)
if rg -n 'debug_pgctx\.js' src/routes/index.ts >/dev/null 2>&1; then
  echo "✅ index.ts already imports debug_pgctx.js"
else
  perl -0777 -i -pe 's/(import type \{ FastifyInstance \} from "fastify";\s*\n)/$1import { debugPgCtxRoutes } from ".\/debug_pgctx.js";\n/s' src/routes/index.ts
  echo "✅ added import in index.ts"
fi

if rg -n 'register\(debugPgCtxRoutes\)' src/routes/index.ts >/dev/null 2>&1; then
  echo "✅ debugPgCtxRoutes already registered"
else
  # register after healthRoutes/webhooksRoutes if present, else after demoRoutes
  perl -0777 -i -pe '
    if (s/(await\s+app\.register\(webhooksRoutes\);\s*\n)/$1  await app.register(debugPgCtxRoutes);\n/s) { }
    elsif (s/(await\s+app\.register\(healthRoutes\);\s*\n)/$1  await app.register(debugPgCtxRoutes);\n/s) { }
    elsif (s/(await\s+app\.register\(demoRoutes[^\n]*\);\s*\n)/$1  await app.register(debugPgCtxRoutes);\n/s) { }
  ' src/routes/index.ts
  echo "✅ registered debugPgCtxRoutes in index.ts"
fi

# ------------------------------------------------------------
# 1) Fix duplicate GET "/" patterns in route files:
#    - If there are TWO app.get("/") in the file, the SECOND one is CREATE
#      and must become app.post("/")
# ------------------------------------------------------------
fix_second_get_root_to_post() {
  local file="$1"
  [ -f "$file" ] || return 0
  backup "$file"

  local count
  count="$(rg -n 'app\.get\(\s*"\s*/\s*"' "$file" | wc -l | tr -d ' ')"
  if [ "${count}" -gt 1 ]; then
    perl -0777 -i -pe '
      my $i=0;
      s/app\.get\(\s*"\s*\/\s*"/(++$i==2) ? "app.post(\"/\"" : $&/ge;
    ' "$file"
    echo "✅ $file: changed 2nd app.get(\"/\") -> app.post(\"/\")"
  else
    echo "ℹ️  $file: GET / count = ${count} (no change)"
  fi
}

fix_second_get_root_to_post "src/routes/properties.ts"
fix_second_get_root_to_post "src/routes/viewings.ts"
fix_second_get_root_to_post "src/routes/applications.ts"
fix_second_get_root_to_post "src/routes/listings.ts"

# ------------------------------------------------------------
# 2) Fix broken listings.ts line: app.post("  -> app.post("/", ...
# ------------------------------------------------------------
if [ -f "src/routes/listings.ts" ]; then
  backup "src/routes/listings.ts"
  # Replace exactly: app.post(", { ...  -> app.post("/", { ...
  perl -0777 -i -pe 's/app\.post\("\s*,\s*\{/app.post("\/", { /g' src/routes/listings.ts
  # Also handle any variant with spaces/newlines between "(" and quote
  perl -0777 -i -pe 's/app\.post\(\s*"\s*,\s*\{/app.post("\/", { /g' src/routes/listings.ts

  if rg -n 'app\.post\("\s*,' src/routes/listings.ts >/dev/null 2>&1; then
    echo "❌ listings.ts still has broken app.post(\" ,"
    echo "    Restore from backup: $BACKUP_DIR/listings.ts"
    exit 1
  else
    echo "✅ listings.ts: fixed broken app.post quote if it existed"
  fi
fi

# ------------------------------------------------------------
# 3) Fix obvious wrong verbs based on comments for known endpoints:
#    - viewings: create should be POST "/", patch should be PATCH "/:id"
#    - applications: create should be POST "/", patch should be PATCH "/:id"
# ------------------------------------------------------------
fix_verbs_by_comment() {
  local file="$1"
  [ -f "$file" ] || return 0
  backup "$file"

  perl -0777 -i -pe '
    s/(\/\/\s*CREATE[^\n]*\n\s*)app\.get\(/$1app.post(/g;
    s/(\/\/\s*CREATE[^\n]*\n\s*)app\.put\(/$1app.post(/g;
    s/(\/\/\s*PATCH[^\n]*\n\s*)app\.get\(/$1app.patch(/g;
    s/(\/\/\s*PATCH[^\n]*\n\s*)app\.post\(/$1app.patch(/g;
  ' "$file"
  echo "✅ $file: adjusted verbs by comments (best-effort)"
}

fix_verbs_by_comment "src/routes/viewings.ts"
fix_verbs_by_comment "src/routes/applications.ts"
fix_verbs_by_comment "src/routes/listings.ts"

echo ""
echo "---- QUICK CHECKS ----"
echo "1) Any broken quote like app.post(\" then newline?"
rg -n 'app\.(get|post|put|patch|delete)\(\s*"\s*$' src/routes && echo "❌ Found broken quote lines above" || echo "✅ No broken quote lines"

echo ""
echo "2) Duplicate GET \"/\" counts (should be <=1 each):"
for f in src/routes/properties.ts src/routes/viewings.ts src/routes/applications.ts src/routes/listings.ts; do
  [ -f "$f" ] || continue
  c="$(rg -n 'app\.get\(\s*"\s*/\s*"' "$f" | wc -l | tr -d ' ')"
  echo " - $f : GET / count = $c"
done

echo ""
echo "============================================================"
echo "✅ DONE. Now run:"
echo "  npm run build"
echo "  # restart server: Ctrl+C then npm run dev"
echo "============================================================"
