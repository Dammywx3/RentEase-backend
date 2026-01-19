#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROUTES="$ROOT/src/routes/purchases.routes.ts"

[ -f "$ROUTES" ] || { echo "❌ Not found: $ROUTES"; exit 1; }

typecheck() {
  npx -y tsc -p "$ROOT/tsconfig.json" --noEmit >/dev/null 2>&1
}

echo "==> Backup current routes"
TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$ROOT/scripts/.bak"
cp "$ROUTES" "$ROOT/scripts/.bak/purchases.routes.ts.bak.before_restore.$TS"
echo "✅ backed up current routes -> scripts/.bak/purchases.routes.ts.bak.before_restore.$TS"

echo "==> Checking if project already typechecks..."
if typecheck; then
  echo "✅ Already typechecks. Nothing to restore."
  exit 0
fi

echo "==> Trying routes backups until TypeScript passes..."
CANDS="$(ls -t "$ROOT"/scripts/.bak/purchases.routes.ts.bak.* 2>/dev/null || true)"

if [ -z "$CANDS" ]; then
  echo "❌ No routes backups found in scripts/.bak/"
  exit 1
fi

# Try each backup newest -> oldest
for f in $CANDS; do
  cp "$f" "$ROUTES"
  if typecheck; then
    echo "✅ Restored routes from: $f"
    echo ""
    echo "NEXT: npm run dev"
    exit 0
  fi
done

echo "❌ None of the backups made tsc pass."
echo "🔎 Showing the error area (lines 240-290) to fix manually:"
nl -ba "$ROUTES" | sed -n '240,290p'
exit 1
