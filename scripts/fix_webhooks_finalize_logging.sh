# scripts/fix_webhooks_finalize_logging.sh
# Adds:
#   const res = await finalizePaystackChargeSuccess(pg, event);
#   if (!res.ok) app.log.warn(res, "paystack finalize result");
#   else app.log.info({ reference: extractPaystackReference(event) }, "paystack finalize ok");
#
# Safe + idempotent: if already present, it won’t duplicate.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE="$ROOT_DIR/src/routes/webhooks.ts"

echo "=== Fix: add finalizePaystackChargeSuccess logging ==="
echo "File: $FILE"

if [ ! -f "$FILE" ]; then
  echo "❌ Not found: $FILE"
  exit 1
fi

# Backup
TS="$(date +%s)"
cp "$FILE" "$FILE.bak.$TS"
echo "Backup: $FILE.bak.$TS"

node <<'NODE'
import fs from "node:fs";

const file = process.env.FILE || "src/routes/webhooks.ts";
let s = fs.readFileSync(file, "utf8");

// If logging already exists, do nothing
if (
  s.includes('app.log.warn(res, "paystack finalize result")') ||
  s.includes('app.log.info({ reference: extractPaystackReference(event) }, "paystack finalize ok")')
) {
  console.log("ℹ️ Logging already present. No changes.");
  process.exit(0);
}

// Target single line call:
const needle = "const res = await finalizePaystackChargeSuccess(pg, event);";

if (!s.includes(needle)) {
  console.error("❌ Patch failed: could not find:", needle);
  console.error("Tip: run:");
  console.error('  rg -n "finalizePaystackChargeSuccess\\(" src/routes/webhooks.ts');
  process.exit(1);
}

const replacement = [
  "const res = await finalizePaystackChargeSuccess(pg, event);",
  'if (!res.ok) app.log.warn(res, "paystack finalize result");',
  'else app.log.info({ reference: extractPaystackReference(event) }, "paystack finalize ok");',
].join("\n");

// Replace ONLY the first occurrence
s = s.replace(needle, replacement);

fs.writeFileSync(file, s, "utf8");
console.log("✅ Patched:", file);
NODE

echo
echo "---- verify ----"
grep -n "finalizePaystackChargeSuccess" -n "$FILE" | head -n 20 || true
grep -n "paystack finalize result" -n "$FILE" | head -n 20 || true
grep -n "paystack finalize ok" -n "$FILE" | head -n 20 || true

echo
echo "✅ Done."