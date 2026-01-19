#!/usr/bin/env bash
set -euo pipefail

FILE="src/routes/purchases.routes.ts"

if [ ! -f "$FILE" ]; then
  echo "❌ Missing $FILE"
  exit 1
fi

# If already properly exported, stop
if grep -qE 'export\s+async\s+function\s+purchasesRoutes\s*\(' "$FILE"; then
  echo "✅ purchasesRoutes wrapper already exists."
else
  echo "❌ purchasesRoutes wrapper missing. Run:"
  echo "   ./scripts/fix_purchases_routes_export.sh"
  exit 1
fi

# If file already contains app.<method>(...) lines outside wrapper, try wrap them.
# This is a simple heuristic: if we find "app." and NO "TODO: move purchases route registrations here."
if grep -qE '\bapp\.(get|post|patch|put|delete)\s*\(' "$FILE"; then
  echo "==> Found route registrations (app.get/post/etc)."
else
  echo "==> No app.get/post/etc found. Nothing to auto-wrap."
  exit 0
fi

BACKUP="$FILE.bak.autowrap.$(date +%s)"
cp "$FILE" "$BACKUP"
echo "==> Backed up -> $BACKUP"

TMP="/tmp/purchases_autowrap_$$.ts"

# Strategy:
# 1) Remove the empty wrapper body
# 2) Move all top-level app.<method>(...) lines into the wrapper body
# NOTE: This will not catch nested plugins, but works for simple files.

perl -0777 -pe '
  # Replace wrapper function body with placeholder
  s/export\s+async\s+function\s+purchasesRoutes\s*\(\s*app:\s*FastifyInstance\s*\)\s*\{\s*[^}]*\}/export async function purchasesRoutes(app: FastifyInstance) {\n__ROUTE_BLOCK__\n}/s;

  # Extract app.<method>(...) statements (very naive)
' "$FILE" > "$TMP"

# Pull out route lines from original file (naive but works for many cases)
ROUTES_TMP="/tmp/purchases_route_lines_$$.txt"
grep -E '^\s*app\.(get|post|patch|put|delete)\s*\(' "$FILE" > "$ROUTES_TMP" || true

if [ ! -s "$ROUTES_TMP" ]; then
  echo "❌ Could not extract any top-level app.<method>(...) lines."
  echo "   You will need to move your route definitions manually."
  rm -f "$TMP" "$ROUTES_TMP"
  exit 1
fi

# Remove those top-level route lines from file (keep everything else)
perl -ne '
  next if /^\s*app\.(get|post|patch|put|delete)\s*\(/;
  print;
' "$TMP" > "$TMP.2"

# Insert extracted lines into wrapper
perl -0777 -pe '
  my $block = do { local $/; open my $fh, "<", $ENV{ROUTES_TMP} or die $!; <$fh> };
  $block =~ s/\n$//;
  s/__ROUTE_BLOCK__/$block/s;
' "$TMP.2" ROUTES_TMP="$ROUTES_TMP" > "$FILE"

rm -f "$TMP" "$TMP.2" "$ROUTES_TMP"

echo "✅ Auto-wrapped extracted routes into purchasesRoutes(app)."
echo "➡️ Now rebuild index and restart server:"
echo "   ./scripts/rebuild_routes_index.sh"
