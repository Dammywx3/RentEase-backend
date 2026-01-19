#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE="$ROOT/src/routes/purchases.routes.ts"

if [[ ! -f "$FILE" ]]; then
  echo "[ERR] File not found: $FILE"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$ROOT/.patch_backups/$TS"
mkdir -p "$BACKUP_DIR"

cp "$FILE" "$BACKUP_DIR/src__routes__purchases.routes.ts"
echo "✅ Backup: $FILE -> $BACKUP_DIR/src__routes__purchases.routes.ts"

python3 - <<'PY'
import re
from pathlib import Path

root = Path(__file__).resolve().parent
# script runs from stdin; use cwd from bash
import os
file_path = Path(os.environ["FILE_PATH"])

s = file_path.read_text(encoding="utf-8").splitlines(True)

# ---------- 1) Remove stray newTotalHeld/currentHeld lines ONLY inside escrow/release handler ----------
out = []
in_release = False

release_start = re.compile(r'"/:purchaseId/escrow/release"')
route_start = re.compile(r'^\s*fastify\.(get|post|put|delete)\(')

for i, line in enumerate(s):
  if release_start.search(line):
    in_release = True

  # when we hit the next route definition AFTER release block, stop being in_release
  if in_release and route_start.search(line) and '"/:purchaseId/escrow/release"' not in line:
    # Note: this can trigger too early only if nested; but your file uses top-level fastify.* calls.
    in_release = False

  if in_release:
    # remove ONLY these accidental lines inside release route
    if re.search(r'\bnewTotalHeld\s*=', line):
      continue
    if re.search(r'\bconst\s+currentHeld\b', line):
      continue

  out.append(line)

text = "".join(out)

# ---------- 2) Fix auto-release platformFeeAmount in /status closed block ----------
# Replace the purchase_escrow_release call inside the "if (newStatus === 'closed')" autoEscrow block
# by injecting server-side fee computation (release delta) right before the call.
pattern = r"""
if\s*\(\s*newStatus\s*===\s*["']closed["']\s*\)\s*\{
(?P<body>[\s\S]*?)
await\s+client\.query\(\s*
`select\s+public\.purchase_escrow_release\(\$1::uuid,\s*\$2::uuid,\s*\$3::numeric,\s*\$4::text,\s*\$5::numeric,\s*\$6::text\);\s*`,\s*
\[\s*purchaseId\s*,\s*orgId\s*,\s*held\s*,\s*refreshed\.currency\s*,\s*platformFeeAmount\s*,\s*note\s*\?\?\s*["']auto\s+escrow\s+release["']\s*\]\s*
\)\s*;
"""

m = re.search(pattern, text, re.VERBOSE)
if m:
  body = m.group("body")
  # Inject fee computation just before the call
  inject = r"""
                // ✅ Server-side fee (do NOT trust client for platform fees)
                // Fee is computed on the RELEASE DELTA (held - alreadyReleased)
                const releaseDelta = Math.max(0, held - alreadyReleased);
                const split = computePlatformFeeSplit({
                  paymentKind: "buy",
                  amount: releaseDelta,
                  currency: refreshed.currency,
                });
                const platformFeeAmount = Number(split.platformFee ?? 0);

                // keep client value only for optional debugging
                void platformFeeAmountFromClient;

"""
  replacement = f"""
if (newStatus === "closed") {{
{body}{inject}                await client.query(
                  `select public.purchase_escrow_release($1::uuid, $2::uuid, $3::numeric, $4::text, $5::numeric, $6::text);`,
                  // DB function expects NEW TOTAL released
                  [purchaseId, orgId, held, refreshed.currency, platformFeeAmount, note ?? "auto escrow release"]
                );
"""
  text = re.sub(pattern, replacement, text, flags=re.VERBOSE)

file_path.write_text(text, encoding="utf-8")
print("✅ Patch applied to purchases.routes.ts")
PY