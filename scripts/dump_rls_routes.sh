#!/usr/bin/env bash
set -euo pipefail

ROOT="src/routes"
OUT="rls_routes_dump.txt"

echo "============================================================" | tee "$OUT"
echo "RentEase: Dump routes that use RLS context (imports + ctx lines)" | tee -a "$OUT"
echo "PWD: $(pwd)" | tee -a "$OUT"
echo "============================================================" | tee -a "$OUT"
echo "" | tee -a "$OUT"

# Find route files that likely touch DB/RLS
FILES="$(rg -l --hidden --glob '!**/*.bak*' --glob '!**/*.map' \
  "withRlsTransaction|app\.pg\.connect\(\)|BEGIN|COMMIT|ROLLBACK|setPgContext" \
  "$ROOT" 2>/dev/null || true)"

if [[ -z "${FILES}" ]]; then
  echo "✅ No RLS/tx usage found in $ROOT" | tee -a "$OUT"
  exit 0
fi

COUNT="$(printf '%s\n' "$FILES" | sed '/^\s*$/d' | wc -l | tr -d ' ')"
echo "Found ${COUNT} route files touching tx/RLS:" | tee -a "$OUT"
printf '%s\n' "$FILES" | sed 's/^/ - /' | tee -a "$OUT"
echo "" | tee -a "$OUT"

# Loop each file safely
printf '%s\n' "$FILES" | sed '/^\s*$/d' | while IFS= read -r f; do
  echo "============================================================" | tee -a "$OUT"
  echo "FILE: $f" | tee -a "$OUT"
  echo "------------------------------------------------------------" | tee -a "$OUT"

  echo "[Imports: withRlsTransaction / setPgContext / app.pg.connect]" | tee -a "$OUT"
  nl -ba "$f" | sed -n '1,120p' | rg -n "withRlsTransaction|setPgContext|app\.pg\.connect\(" -S || true
  echo "" | tee -a "$OUT"

  echo "[CTX extraction lines: req.user / req.orgId / x-organization-id / headers]" | tee -a "$OUT"
  nl -ba "$f" | rg -n "req\.user|req\.orgId|x-organization-id|headers|authorization|Bearer" -S || true
  echo "" | tee -a "$OUT"

  echo "[Transaction usage: withRlsTransaction / BEGIN / COMMIT / ROLLBACK]" | tee -a "$OUT"
  nl -ba "$f" | rg -n "withRlsTransaction|BEGIN|COMMIT|ROLLBACK" -S || true
  echo "" | tee -a "$OUT"

  echo "[Route handlers: app.get/app.post/app.patch/app.put]" | tee -a "$OUT"
  nl -ba "$f" | rg -n "app\.(get|post|patch|put|delete)\(" -S || true
  echo "" | tee -a "$OUT"
done

echo "============================================================" | tee -a "$OUT"
echo "✅ Saved to: $OUT" | tee -a "$OUT"
echo "Now run: cat $OUT" | tee -a "$OUT"
