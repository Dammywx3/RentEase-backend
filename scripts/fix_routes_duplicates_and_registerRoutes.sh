#!/usr/bin/env bash
set -euo pipefail

PURCHASES_FILE="src/routes/purchases.routes.ts"
INDEX_FILE="src/routes/index.ts"

if [ ! -f "$PURCHASES_FILE" ]; then
  echo "❌ Missing: $PURCHASES_FILE"
  exit 1
fi
if [ ! -f "$INDEX_FILE" ]; then
  echo "❌ Missing: $INDEX_FILE"
  exit 1
fi

echo "==> 0) Backups..."
cp "$PURCHASES_FILE" "$PURCHASES_FILE.bak.$(date +%s)"
cp "$INDEX_FILE" "$INDEX_FILE.bak.$(date +%s)"
echo "✅ Backed up purchases + index"

echo
echo "==> 1) Fix purchases.routes.ts duplicate function name..."
# Convert the real default export to a named export:
#   export default async function purchasesRoutes(...)  -> export async function purchasesRoutes(...)
# only the FIRST occurrence
perl -0777 -i -pe '
  my $done = 0;
  s/export\s+default\s+async\s+function\s+purchasesRoutes\s*\(/$done++ ? $& : "export async function purchasesRoutes("/e;
' "$PURCHASES_FILE"

# Remove the auto-added empty wrapper block if present (added by helper script)
# It starts with the marker comment and defines export async function purchasesRoutes(app: FastifyInstance)
perl -0777 -i -pe '
  s/\n\/\/ -----------------------------------------------------------------------------\n\/\/ ✅ Auto-added wrapper so src\/routes\/index\.ts can register this file reliably\.\n\/\/ Move your purchases routes registration into this function\.\n\/\/ -----------------------------------------------------------------------------\n\nexport async function purchasesRoutes\s*\(\s*app:\s*FastifyInstance\s*\)\s*\{\n.*?\n\}\n//s;
' "$PURCHASES_FILE"

# Also remove any SECOND accidental purchasesRoutes wrapper if it exists (fallback)
# If there are still 2+ matches, delete the last one (best-effort)
COUNT="$(grep -cE 'export\s+(default\s+)?async\s+function\s+purchasesRoutes\s*\(' "$PURCHASES_FILE" || true)"
if [ "${COUNT:-0}" -gt 1 ]; then
  echo "⚠️ Still found $COUNT purchasesRoutes declarations. Removing the last one (best-effort)..."
  # delete from the LAST "export async function purchasesRoutes(" to end of its block
  # (naive but works for the wrapper we added)
  perl -0777 -i -pe '
    my $s = $_;
    my $pos = rindex($s, "export async function purchasesRoutes(");
    if ($pos >= 0) {
      substr($s, $pos) =~ s/^export async function purchasesRoutes\([^}]*\}\n?//s;
      $_ = substr($s, 0, $pos) . substr($s, $pos);
    }
  ' "$PURCHASES_FILE"
fi

echo "✅ purchases.routes.ts updated."
echo "==> Quick check: occurrences now:"
grep -nE 'export\s+(default\s+)?async\s+function\s+purchasesRoutes\s*\(' "$PURCHASES_FILE" || true

echo
echo "==> 2) Ensure src/routes/index.ts exports registerRoutes (to satisfy src/server.ts)..."
# If registerRoutes already exists, do nothing
if grep -qE 'export\s+(async\s+)?function\s+registerRoutes\s*\(|export\s+const\s+registerRoutes\s*=' "$INDEX_FILE"; then
  echo "✅ registerRoutes already exists in routes/index.ts"
else
  # Insert alias export right before "export default routes;"
  perl -0777 -i -pe '
    s/\nexport default routes;\n/\n\/\/ Backwards-compatible alias (some files import { registerRoutes })\nexport const registerRoutes = routes;\n\nexport default routes;\n/s;
  ' "$INDEX_FILE"
  echo "✅ Added: export const registerRoutes = routes;"
fi

echo
echo "==> 3) Quick sanity preview (relevant parts)"
echo "--- purchases.routes.ts exports ---"
grep -nE 'export\s+(default\s+)?async\s+function\s+purchasesRoutes' "$PURCHASES_FILE" | head -n 20 || true
echo
echo "--- index.ts registerRoutes ---"
grep -nE 'registerRoutes|export default routes|export async function routes' "$INDEX_FILE" | sed -n '1,120p' || true

echo
echo "==> 4) Optional: run TypeScript noEmit check (won't stop script if it fails)"
if [ -f "tsconfig.json" ]; then
  npx -y tsc -p tsconfig.json --noEmit || true
else
  echo "No tsconfig.json found, skipping tsc."
fi

echo
echo "✅ Done."
echo "Next:"
echo "  1) ./scripts/rebuild_routes_index.sh"
echo "  2) Restart server"
