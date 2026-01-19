#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

FILE="src/routes/purchases.routes.ts"
if [ ! -f "$FILE" ]; then
  echo "❌ File not found: $FILE"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP="$FILE.bak.${TS}"
cp "$FILE" "$BACKUP"
echo "==> Backup created: $BACKUP"

# Insert set_config('app.event_note'...) right after setPgContext in the /status route.
perl -0777 -i -pe '
  s@
(\s*await\s+setPgContext\(client,\s*\{\s*userId:\s*actorUserId,\s*organizationId:\s*orgId\s*\}\);\s*\n)
@
$1
      // Optional: pass a note to the DB trigger via session setting (cleared after request)
      if (typeof note === "string" && note.trim().length > 0) {
        await client.query("select set_config(\x27app.event_note\x27, $1, false)", [note.trim()]);
      } else {
        await client.query("select set_config(\x27app.event_note\x27, \x27\x27, false)");
      }

@gs
' "$FILE"

# Ensure we clear app.event_note in finally before release (to avoid pooled-connection leakage)
perl -0777 -i -pe '
  s@
(\s*finally\s*\{\s*\n)(\s*client\.release\(\);\s*\n\s*\})
@
$1
      try {
        await client.query("select set_config(\x27app.event_note\x27, \x27\x27, false)");
      } catch {}
$2
@gs
' "$FILE"

echo "✅ Patched: $FILE (sets/clears app.event_note for /status route)"
echo "==> Verify around /status route:"
grep -n "/purchases/:purchaseId/status" -n "$FILE" | head -n 5 || true
