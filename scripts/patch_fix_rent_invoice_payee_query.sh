#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# Fix: paystack_finalize.service.ts has "select select" typo
# Replaces the broken rent-invoice payee query with the correct one.
# Creates a backup under .patch_backups/<timestamp>/
# ------------------------------------------------------------

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FILE="src/services/paystack_finalize.service.ts"

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$ROOT/.patch_backups/$TS"
mkdir -p "$BACKUP_DIR"

say() { printf "\n\033[1m%s\033[0m\n" "$*"; }
ok()  { printf "✅ %s\n" "$*"; }
die() { printf "❌ %s\n" "$*"; exit 1; }

[[ -f "$FILE" ]] || die "Missing file: $FILE"

# backup
DEST="$BACKUP_DIR/${FILE//\//__}"
cp -a "$FILE" "$DEST"
ok "Backup: $FILE -> $DEST"

python3 - "$FILE" <<'PY'
import pathlib, re, sys

path = pathlib.Path(sys.argv[1])
src = path.read_text(encoding="utf-8")
orig = src

# We target ONLY the rent_invoice branch query block by matching:
# if (payment.reference_type === "rent_invoice" && payment.reference_id) { ... const r = await client.query ... }
pattern = re.compile(
    r"""
(?P<before>if\s*\(\s*payment\.reference_type\s*===\s*["']rent_invoice["']\s*&&\s*payment\.reference_id\s*\)\s*\{\s*)
(?P<body>[\s\S]*?)
(?P<after>\n\s*\}\s*else\s+if\s*\(\s*payment\.reference_type\s*===\s*["']purchase["'])
""",
    re.VERBOSE,
)

m = pattern.search(src)
if not m:
    raise SystemExit("[ABORT] Could not find rent_invoice -> purchase branch block to patch (pattern mismatch).")

before = m.group("before")
after  = m.group("after")

# Replace the whole inner body of the rent_invoice branch with a clean, correct query.
replacement_body = r"""
    const r = await client.query<{ payee_user_id: string | null }>(
      `
      select
        p.owner_id::text as payee_user_id
      from public.rent_invoices ri
      join public.properties p on p.id = ri.property_id
      where ri.id = $1::uuid
        and ri.organization_id = $2::uuid
        and ri.deleted_at is null
      limit 1;
      `,
      [payment.reference_id, orgId]
    );
    payeeUserId = r.rows[0]?.payee_user_id ?? null;
""".rstrip()

src = src[:m.start()] + before + replacement_body + after + src[m.end():]

if src == orig:
    raise SystemExit("[ABORT] No changes applied (patch did nothing).")

# Extra safety: ensure we removed "select\n      select" somewhere in file
if re.search(r"\bselect\s*\n\s*select\b", src, flags=re.IGNORECASE):
    raise SystemExit("[ABORT] Still found 'select select' after patch — refusing to write.")

path.write_text(src, encoding="utf-8")
print(f"[OK] Patched {path}")
PY

ok "Patch applied."

echo
echo "Sanity check (should show NO 'select select'):"
rg -n "select[[:space:]]*\n[[:space:]]*select" "$FILE" || true

echo
echo "Show the rent_invoice query block (around it):"
nl -ba "$FILE" | sed -n '220,280p' || true

echo
ok "Done."