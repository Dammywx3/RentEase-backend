#!/usr/bin/env bash
set -euo pipefail

INDEX_FILE="src/routes/index.ts"
ROUTES_DIR="src/routes"

if [ ! -d "$ROUTES_DIR" ]; then
  echo "❌ Missing routes directory: $ROUTES_DIR"
  exit 1
fi

# Backup existing index.ts if present
if [ -f "$INDEX_FILE" ]; then
  cp "$INDEX_FILE" "$INDEX_FILE.bak.$(date +%s)"
  echo "==> Backed up index.ts -> $INDEX_FILE.bak.*"
fi

# Helper: get exported async function name from a route file
get_exported_async_fn() {
  local f="$1"
  # Grabs first "export async function NAME(" occurrence
  perl -ne 'if (/export\s+async\s+function\s+([A-Za-z0-9_]+)\s*\(/) { print $1; exit }' "$f" || true
}

# Map a route file to where it should be registered
# Prints: "SCOPE PREFIX"
#   SCOPE: root | v1
#   PREFIX: fastify register prefix (string; can be empty "")
route_scope_and_prefix() {
  local base="$1"
  case "$base" in
    # root-level
    demo.ts)       echo "root /demo" ;;
    health.ts)     echo "root " ;;
    webhooks.ts)   echo "root " ;;

    # v1 routes (standard)
    auth.ts)            echo "v1 /auth" ;;
    me.ts)              echo "v1 /me" ;;
    organizations.ts)   echo "v1 /organizations" ;;
    payments.ts)        echo "v1 /payments" ;;
    properties.ts)      echo "v1 /properties" ;;
    listings.ts)        echo "v1 /listings" ;;
    applications.ts)    echo "v1 /applications" ;;
    rent_invoices.ts)   echo "v1 /rent-invoices" ;;
    tenancies.ts)       echo "v1 /tenancies" ;;
    viewings.ts)        echo "v1 /viewings" ;;

    # purchase helpers that assume prefix /purchases
    purchase_escrow.ts) echo "v1 /purchases" ;;
    purchase_close.ts)  echo "v1 /purchases" ;;

    # IMPORTANT:
    # purchases.routes.ts already defines paths like "/purchases", so prefix must be EMPTY
    purchases.routes.ts) echo "v1 " ;;

    # fallback: put under v1 with "/<filename-without-ext>"
    *)
      local name="${base%.ts}"
      echo "v1 /$name"
      ;;
  esac
}

# Collect imports and registrations
IMPORTS=""
ROOT_REG=""
V1_REG=""

# Order matters a bit (stable & predictable):
# We'll sort by filename so rebuild is deterministic.
FILES="$(ls -1 "$ROUTES_DIR"/*.ts 2>/dev/null | sort || true)"

if [ -z "$FILES" ]; then
  echo "❌ No route files found in $ROUTES_DIR"
  exit 1
fi

while IFS= read -r f; do
  base="$(basename "$f")"

  # Skip index.ts itself
  if [ "$base" = "index.ts" ]; then
    continue
  fi

  fn="$(get_exported_async_fn "$f")"
  if [ -z "$fn" ]; then
    echo "==> Skipping (no export async function found): $base"
    continue
  fi

  # Build import (use .js because your TS runtime compiles/loads ESM js paths)
  mod="./${base%.ts}.js"
  IMPORTS="${IMPORTS}import { ${fn} } from \"${mod}\";\n"

  read -r scope prefix <<<"$(route_scope_and_prefix "$base")"

  # Build registration lines
  if [ "$scope" = "root" ]; then
    if [ -n "${prefix:-}" ]; then
      ROOT_REG="${ROOT_REG}  await app.register(${fn}, { prefix: \"${prefix}\" });\n"
    else
      ROOT_REG="${ROOT_REG}  await app.register(${fn});\n"
    fi
  else
    if [ -n "${prefix:-}" ]; then
      V1_REG="${V1_REG}    await v1.register(${fn}, { prefix: \"${prefix}\" });\n"
    else
      V1_REG="${V1_REG}    await v1.register(${fn});\n"
    fi
  fi
done <<< "$FILES"

# Write index.ts
{
  echo "import type { FastifyInstance } from \"fastify\";"
  echo
  # shell-safe printf so \n is honored
  printf "%b" "$IMPORTS"
  echo
  echo "export async function routes(app: FastifyInstance) {"
  echo "  // Root-level routes"
  printf "%b" "$ROOT_REG"
  echo
  echo "  // Versioned API"
  echo "  await app.register(async function v1(v1) {"
  printf "%b" "$V1_REG"
  echo "  }, { prefix: \"/v1\" });"
  echo "}"
  echo
  echo "// Backwards-compatible alias (src/server.ts imports { registerRoutes })"
  echo "export const registerRoutes = routes;"
  echo
  echo "export default routes;"
} > "$INDEX_FILE"

echo
echo "✅ Rebuilt $INDEX_FILE (and preserved registerRoutes)"
echo "==> Quick preview (first 160 lines):"
nl -ba "$INDEX_FILE" | sed -n '1,160p'
echo
echo "➡️ Next:"
echo "  1) Restart server"
echo "  2) If any error: run ./scripts/health_check.sh and paste the first error lines"
