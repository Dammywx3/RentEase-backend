#!/usr/bin/env bash
set -euo pipefail

FILE="src/routes/purchases.routes.ts"

if [ ! -f "$FILE" ]; then
  echo "❌ Missing $FILE"
  exit 1
fi

echo "==> Inspecting $FILE ..."

# Show first 120 lines for context
echo
echo "---- TOP OF FILE (first 120 lines) ----"
nl -ba "$FILE" | sed -n '1,120p'
echo "--------------------------------------"
echo

# Check if it already has "export async function"
if grep -qE 'export\s+async\s+function\s+[A-Za-z0-9_]+\s*\(' "$FILE"; then
  echo "✅ $FILE already exports an async function. Nothing to do."
  echo "➡️ Re-run your rebuild script to register it:"
  echo "   ./scripts/rebuild_routes_index.sh"
  exit 0
fi

# If it exports default / const etc, we will wrap it.
# We'll create a safe wrapper plugin and keep existing exports.

BACKUP="$FILE.bak.$(date +%s)"
cp "$FILE" "$BACKUP"
echo "==> Backed up -> $BACKUP"

# Determine if it exports a default function/plugin or a named const
# We'll search common patterns.
HAS_DEFAULT="$(grep -cE 'export\s+default\s+' "$FILE" || true)"
HAS_NAMED_PLUGIN="$(grep -cE 'export\s+const\s+(purchasesRoutes|purchaseRoutes)\s*=' "$FILE" || true)"
HAS_REGISTER_CALLS="$(grep -cE '\.get\(|\.post\(|\.patch\(|\.put\(|\.delete\(' "$FILE" || true)"

WRAPPER_NAME="purchasesRoutes"

# Build wrapper appended at end. Try to call existing export if present, else no-op.
# We'll also ensure FastifyInstance import exists.
if ! grep -qE 'import\s+type\s+\{\s*FastifyInstance\s*\}\s+from\s+"fastify"' "$FILE" \
  && ! grep -qE 'import\s+type\s+\{\s*FastifyInstance\s*\}\s+from\s+\x27fastify\x27' "$FILE"; then
  # Add import at top
  TMP="/tmp/purchases_routes_tmp_$$.ts"
  {
    echo 'import type { FastifyInstance } from "fastify";'
    echo
    cat "$FILE"
  } > "$TMP"
  mv "$TMP" "$FILE"
fi

# If file has export default something, we will call it.
# If file has named export const purchasesRoutes/purchaseRoutes, we will call it.
# Otherwise, we will try to detect an existing function name and call it, but safe fallback is to keep routes as-is.
APPEND="/tmp/purchases_routes_append_$$.txt"

cat > "$APPEND" <<'TS'

// -----------------------------------------------------------------------------
// ✅ Auto-added wrapper so src/routes/index.ts can register this file reliably.
// This wrapper calls existing exports if present.
// -----------------------------------------------------------------------------

export async function purchasesRoutes(app: FastifyInstance) {
  // If this file already defines routes directly on a Fastify plugin-style function,
  // migrate that logic into this wrapper later.
  // For now, we try to call any existing exported plugin patterns.

  // @ts-ignore - best-effort interop
  const mod: any = await import("./purchases.routes.js").catch(() => null);

  // If this import trick fails (circular), fall back to calling known locals.
  // Most codebases won't need this import; it's just defensive.

  // If there is a default export function(plugin)
  if (mod && typeof mod.default === "function") {
    await mod.default(app);
    return;
  }

  // If there is a named export purchasesRoutes or purchaseRoutes as a function
  if (mod && typeof mod.purchasesRoutes === "function") {
    await mod.purchasesRoutes(app);
    return;
  }
  if (mod && typeof mod.purchaseRoutes === "function") {
    await mod.purchaseRoutes(app);
    return;
  }

  // If there is a const plugin (fastify accepts fn), call it
  if (mod && typeof mod.purchasesRoutes === "object" && typeof mod.purchasesRoutes === "function") {
    await mod.purchasesRoutes(app);
    return;
  }

  // If no callable export exists, do nothing.
  // That means this file likely registers routes in some other file already.
}
TS

# The import("./purchases.routes.js") line would cause self-import recursion if used.
# So we will NOT keep that approach. We'll instead add a simpler wrapper and let user move logic in.
# Replace append with safer wrapper.

cat > "$APPEND" <<'TS'

// -----------------------------------------------------------------------------
// ✅ Auto-added wrapper so src/routes/index.ts can register this file reliably.
// Move your purchases routes registration into this function.
// -----------------------------------------------------------------------------

export async function purchasesRoutes(app: FastifyInstance) {
  // TODO: move purchases route registrations here.
  // This is intentionally empty to avoid circular imports.
  // If your purchases routes are currently defined elsewhere, you can delete this wrapper.
}
TS

# Append wrapper at end only if not already there
if ! grep -qE 'export\s+async\s+function\s+purchasesRoutes\s*\(' "$FILE"; then
  echo >> "$FILE"
  cat "$APPEND" >> "$FILE"
fi

rm -f "$APPEND"

echo "✅ Added wrapper export async function purchasesRoutes(app)"
echo
echo "➡️ Now you MUST move the actual route registrations into purchasesRoutes(app)."
echo "   (Because right now it’s empty)"
echo
echo "Next: open the file and paste what’s inside your current purchases routing logic into purchasesRoutes(app)."
echo
echo "Then rebuild index:"
echo "  ./scripts/rebuild_routes_index.sh"
