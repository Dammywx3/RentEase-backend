#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
STAMP="$(date +%Y%m%d_%H%M%S)"
BAK_DIR="$ROOT/scripts/.bak"
mkdir -p "$BAK_DIR"

SERVER="$ROOT/src/server.ts"
ROUTES="$ROOT/src/routes/purchases.routes.ts"

backup() {
  local f="$1"
  if [[ -f "$f" ]]; then
    cp -p "$f" "$BAK_DIR/$(basename "$f").bak.$STAMP"
    echo "✅ backup -> $BAK_DIR/$(basename "$f").bak.$STAMP"
  fi
}

echo "==> ROOT=$ROOT"
echo "==> backups in $BAK_DIR ($STAMP)"

# ------------------------------------------------------------
# 1) Fix server.ts crash: remove the injected global hook block
# ------------------------------------------------------------
if [[ -f "$SERVER" ]]; then
  backup "$SERVER"

  python3 - <<'PY'
from pathlib import Path
import re

p = Path("src/server.ts")
t = p.read_text(encoding="utf-8")

# Remove the block we inserted previously (marker-based)
pattern = re.compile(
    r"\n?// --- DB session context for RLS/audit triggers ---.*?\n\}\);\n",
    re.DOTALL
)

new_t, n = pattern.subn("\n", t, count=1)

# If marker not found, also try removing any top-level fastify.addHook('preHandler'...) block
if n == 0:
    pattern2 = re.compile(
        r"\n?fastify\.addHook\(\s*[\"']preHandler[\"']\s*,\s*async\s*\(request\)\s*=>\s*\{.*?\}\s*\);\n",
        re.DOTALL
    )
    new_t, n = pattern2.subn("\n", t, count=1)

p.write_text(new_t, encoding="utf-8")
print(f"✅ server.ts patched (removed injected hook blocks: {n})")
PY
else
  echo "⚠️ src/server.ts not found, skipping server.ts patch"
fi

# ------------------------------------------------------------
# 2) Patch purchases.routes.ts: set DB session vars on SAME client
# ------------------------------------------------------------
if [[ ! -f "$ROUTES" ]]; then
  echo "❌ Cannot find $ROUTES"
  exit 1
fi

backup "$ROUTES"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("src/routes/purchases.routes.ts")
t = p.read_text(encoding="utf-8")

def inject_after_connect(block: str, actor_var: str):
    """
    After: const client = await fastify.pg.connect();
    Insert: await client.query(set_config...) using actor_var and orgId
    """
    insert = f"""
      // --- Set DB session context for triggers/RLS (must be on SAME connection) ---
      await client.query("select set_config('app.user_id', $1, true)", [String({actor_var} ?? "")]);
      await client.query("select set_config('app.organization_id', $1, true)", [String(orgId ?? "")]);
"""
    # Only inject once per block if not already present
    if "set_config('app.user_id'" in block:
        return block

    block = block.replace(
        "const client = await fastify.pg.connect();",
        "const client = await fastify.pg.connect();" + insert
    )
    return block

# Patch PAY handler block
pay_pat = re.compile(
    r'(fastify\.post<\{.*?\}\>\(\s*"/purchases/:purchaseId/pay".*?async\s*\(request,\s*reply\)\s*=>\s*\{.*?\n\s*\}\s*\)\s*;)',
    re.DOTALL
)
m = pay_pat.search(t)
if m:
    pay_block = m.group(1)
    # actor from JWT
    # ensure we have requireAuth already in your file (you do)
    pay_block2 = pay_block
    # add actor variable near start of handler if not present
    if "const actorUserId" not in pay_block2:
        pay_block2 = pay_block2.replace(
            "const { purchaseId } = request.params;",
            "const { purchaseId } = request.params;\n\n      const actorUserId = (request as any).user?.userId ?? null;"
        )
    pay_block2 = inject_after_connect(pay_block2, "actorUserId")
    t = t.replace(pay_block, pay_block2)

# Patch REFUND handler block
refund_pat = re.compile(
    r'(fastify\.post<\{.*?\}\>\(\s*"/purchases/:purchaseId/refund".*?async\s*\(request,\s*reply\)\s*=>\s*\{.*?\n\s*\}\s*\)\s*;)',
    re.DOTALL
)
m2 = refund_pat.search(t)
if m2:
    refund_block = m2.group(1)
    # your refund handler already sets refundedByUserId from JWT
    if "const refundedByUserId" not in refund_block:
        # best effort: create it
        refund_block = refund_block.replace(
            "const refundPaymentId = request.body?.refundPaymentId ?? null;",
            "const refundPaymentId = request.body?.refundPaymentId ?? null;\n\n      const refundedByUserId = (request as any).user?.userId ?? null;"
        )
    refund_block2 = inject_after_connect(refund_block, "refundedByUserId")
    t = t.replace(m2.group(1), refund_block2)

p.write_text(t, encoding="utf-8")
print("✅ purchases.routes.ts patched (set_config on request DB client for pay + refund)")
PY

echo
echo "✅ Fix applied."
echo "Next:"
echo "  1) Restart server: npm run dev"
echo "  2) Re-test pay/refund"
