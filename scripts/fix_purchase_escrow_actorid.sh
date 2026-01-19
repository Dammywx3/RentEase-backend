#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "=== Fix: purchase_escrow actorUserId (robust) ==="
echo "PWD: $(pwd)"

FILE="src/routes/purchase_escrow.ts"
if [[ ! -f "$FILE" ]]; then
  echo "❌ Missing file: $FILE"
  exit 1
fi

BK="${FILE}.bak.$(date +%s)"
cp -v "$FILE" "$BK"

node <<'NODE'
import fs from "node:fs";

const file = "src/routes/purchase_escrow.ts";
let s = fs.readFileSync(file, "utf8");

// Find the call block: releasePurchaseEscrow(client, { ... })
const re = /releasePurchaseEscrow\s*\(\s*client\s*,\s*\{([\s\S]*?)\}\s*\)/m;
const m = s.match(re);

if (!m) {
  console.error("❌ Patch failed: could not find any releasePurchaseEscrow(client, { ... }) call.");
  console.error("Run: rg -n \"releasePurchaseEscrow\" src/routes/purchase_escrow.ts");
  process.exit(1);
}

const inside = m[1];

// If actorUserId already present, stop (idempotent)
if (/actorUserId\s*:/.test(inside)) {
  console.log("✅ No change needed: actorUserId already present.");
  process.exit(0);
}

// Insert actorUserId near the top of the object for clarity
// Prefer inserting after purchaseId if purchaseId exists, else at start.
let patchedInside = inside;

if (/purchaseId\s*:/.test(inside)) {
  patchedInside = inside.replace(/(purchaseId\s*:\s*[^,\n}]+,\s*)/m, `$1  actorUserId: actorId,\n  `);
} else {
  patchedInside = `\n  actorUserId: actorId,\n${inside}`;
}

// Rebuild the full call with patched object
const patchedCall = `releasePurchaseEscrow(client, {${patchedInside}})`;
s = s.replace(re, patchedCall);

fs.writeFileSync(file, s);
console.log("✅ Patched:", file);
NODE

echo
echo "---- verify ----"
if command -v rg >/dev/null 2>&1; then
  rg -n "releasePurchaseEscrow\\(|actorUserId\\s*:" "$FILE" || true
else
  grep -n "releasePurchaseEscrow(" "$FILE" || true
  grep -n "actorUserId" "$FILE" || true
fi

echo
echo "---- TypeScript check ----"
npx tsc -p tsconfig.json --noEmit

echo
echo "✅ Done."
