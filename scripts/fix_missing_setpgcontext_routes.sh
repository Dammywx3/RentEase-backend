#!/usr/bin/env bash
set -u

ts="$(date +%s)"
echo "==> Fix missing setPgContext on selected routes (Option A: BEGIN + SET LOCAL + setPgContext LOCAL)"
echo "==> Timestamp: $ts"

backup() {
  local f="$1"
  if [ -f "$f" ]; then
    cp "$f" "$f.bak.$ts"
    echo "   - backup: $f -> $f.bak.$ts"
  fi
}

ensure_import_setpg() {
  local f="$1"
  # Only add import if not present
  if ! grep -q "setPgContext" "$f"; then
    # Add near the top after other imports (simple + safe insertion)
    perl -0777 -i -pe 's/(^import[\s\S]*?\n\n)/$1import { setPgContext } from "..\/db\/set_pg_context.js";\n\n/m' "$f"
    echo "   - added import setPgContext to $f"
  fi
}

detect_req_var() {
  local f="$1"
  # Prefer "request" if present, otherwise "req"
  if grep -Eq "async\s*\(\s*request\s*," "$f"; then
    echo "request"
    return
  fi
  if grep -Eq "async\s*\(\s*req\s*," "$f"; then
    echo "req"
    return
  fi
  # fallback: Fastify handlers sometimes use (request, reply) but this is safest fallback
  echo "request"
}

insert_rls_context_after_begin() {
  local f="$1"
  local reqvar="$2"

  # If already calls setPgContext somewhere, skip
  if grep -q "setPgContext\\(" "$f"; then
    echo "   - skip (already has setPgContext): $f"
    return
  fi

  # Only patch files that clearly require auth/org (preHandler authenticate)
  if ! grep -Eq "preHandler:\\s*\\[\\s*.*authenticate" "$f"; then
    echo "   - skip (no authenticate preHandler detected): $f"
    return
  fi

  # Insert block right after BEGIN (first occurrence only)
  # Also ensure we set LOCAL timezone + setPgContext using req.orgId and req.user
  perl -0777 -i -pe '
    my $reqvar = $ENV{REQVAR};
    s/\bawait\s+client\.query\(\s*["'\''"]BEGIN["'\''"]\s*\)\s*;\s*/$&\n        await client.query("SET LOCAL TIME ZONE '\''UTC'\''");\n\n        const __actorId = String(('"$reqvar"' as any)?.user?.userId ?? ('"$reqvar"' as any)?.user?.id ?? "").trim();\n        const __orgId = String(('"$reqvar"' as any)?.orgId ?? "").trim();\n\n        if (!__actorId) {\n          const e: any = new Error("Missing authenticated user");\n          e.code = "UNAUTHORIZED";\n          throw e;\n        }\n        if (!__orgId) {\n          const e: any = new Error("Organization not resolved (x-organization-id/orgId)");\n          e.code = "ORG_REQUIRED";\n          throw e;\n        }\n\n        await setPgContext(client, {\n          userId: __actorId,\n          organizationId: __orgId,\n          role: (('"$reqvar"' as any)?.user?.role ?? null) as any,\n        });\n\n/sm
  ' "$f"

  echo "   - inserted setPgContext block after BEGIN in $f (req var: $reqvar)"
}

FILES=(
  "src/routes/payments.ts"
  "src/routes/rent_invoices.ts"
  "src/routes/purchase_escrow.ts"
)

for f in "${FILES[@]}"; do
  if [ ! -f "$f" ]; then
    echo "⚠️ missing: $f (skipping)"
    continue
  fi

  backup "$f"
  ensure_import_setpg "$f"

  reqvar="$(detect_req_var "$f")"
  export REQVAR="$reqvar"
  insert_rls_context_after_begin "$f" "$reqvar"
done

echo ""
echo "==> Done patching 3 route files."
echo "Next run:"
echo "  npm run build"
echo "  npm run dev"
