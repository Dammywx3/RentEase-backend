#!/usr/bin/env bash
# scripts/audit_rls_context_safe.sh
# Run: bash scripts/audit_rls_context_safe.sh
# Output also saved to: rls_audit_output.txt

set -u
ROOT="${1:-src}"

OUT="rls_audit_output.txt"
: > "$OUT"

log() { echo "$*" | tee -a "$OUT"; }

section () {
  log ""
  log "============================================================"
  log "$1"
  log "============================================================"
}

count_in_file () {
  local file="$1"
  local pattern="$2"
  grep -EIn "$pattern" "$file" 2>/dev/null | wc -l | tr -d ' '
}

section "RentEase RLS Audit (SAFE MODE)"
log "Root: $ROOT"
log "PWD : $(pwd)"
log ""

if [ ! -d "$ROOT" ]; then
  log "❌ Folder not found: $ROOT"
  log "Usage: $0 [src]"
  log "✅ Done."
  exit 0
fi

section "1) Route files overview (BEGIN/COMMIT vs setPgContext vs withRlsTransaction)"

ROUTE_DIR="$ROOT/routes"
if [ ! -d "$ROUTE_DIR" ]; then
  log "⚠️ No routes folder found at: $ROUTE_DIR"
else
  ROUTE_FILES=$(find "$ROUTE_DIR" -type f \( -name "*.ts" -o -name "*.js" \) 2>/dev/null | sort || true)

  if [ -z "${ROUTE_FILES:-}" ]; then
    log "⚠️ No route files found under $ROUTE_DIR"
  else
    printf "%-55s | %6s | %6s | %10s | %10s | %10s | %10s\n" \
      "FILE" "BEGIN" "COMMIT" "ROLLBACK" "setPgCtx" "withRlsTx" "pg.connect" | tee -a "$OUT"

    printf "%-55s-+-%6s-+-%6s-+-%10s-+-%10s-+-%10s-+-%10s\n" \
      "$(printf '%.0s-' {1..55})" "------" "------" "----------" "----------" "----------" "----------" | tee -a "$OUT"

    while IFS= read -r f; do
      b=$(count_in_file "$f" "client\.query\(\s*['\"]BEGIN['\"]\s*\)|\bBEGIN\b")
      c=$(count_in_file "$f" "client\.query\(\s*['\"]COMMIT['\"]\s*\)|\bCOMMIT\b")
      r=$(count_in_file "$f" "client\.query\(\s*['\"]ROLLBACK['\"]\s*\)|\bROLLBACK\b")
      s=$(count_in_file "$f" "setPgContext\s*\(")
      w=$(count_in_file "$f" "withRlsTransaction\s*\(|withRlsTx\s*\(|withAppRlsTx\s*\(")
      p=$(count_in_file "$f" "app\.pg\.connect\s*\(|fastify\.pg\.connect\s*\(")

      printf "%-55s | %6s | %6s | %10s | %10s | %10s | %10s\n" \
        "${f#$ROOT/}" "$b" "$c" "$r" "$s" "$w" "$p" | tee -a "$OUT"
    done <<< "$ROUTE_FILES"
  fi
fi

section "2) Direct set_config usage outside src/db/set_pg_context.* (should be centralized)"
SETCFG=$(grep -RIn "set_config\(" "$ROOT" 2>/dev/null | grep -vE "src/db/set_pg_context\.(ts|js)" || true)
if [ -z "${SETCFG:-}" ]; then
  log "✅ No direct set_config() calls found outside set_pg_context."
else
  log "⚠️ Found direct set_config() usage outside set_pg_context:"
  log "$SETCFG"
fi

section "3) RLS key usage (org/user keys)"
grep -RIn "app\.organization_id|app\.current_organization|app\.current_user|app\.user_id|current_user_uuid|current_organization_uuid" \
  "$ROOT" 2>/dev/null | tee -a "$OUT" || true

section "4) Auth attachment points"
log "authenticate decorator:"
grep -RIn "decorate\(\s*['\"]authenticate['\"]" "$ROOT" 2>/dev/null | tee -a "$OUT" || true
log ""
log "requireAuth/optionalAuth:"
grep -RIn "export async function requireAuth|export async function optionalAuth" "$ROOT/middleware" 2>/dev/null | tee -a "$OUT" || true

section "5) DONE"
log "✅ Saved output to: $OUT"
log "Now paste me either:"
log " - the terminal output, OR"
log " - the file contents: cat $OUT"
log ""
log "✅ Done."
exit 0