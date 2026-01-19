#!/usr/bin/env bash
set -euo pipefail

echo "== Fix rent invoice PAY route: ensure req.user via jwtVerify =="

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILE="$ROOT/src/routes/rent_invoices.ts"

if [ ! -f "$FILE" ]; then
  echo "ERROR: $FILE not found"
  exit 1
fi

# If already patched, do nothing
if grep -q "AUTH_GUARD_RENT_INVOICE_PAY" "$FILE"; then
  echo "✅ Already patched (marker found)."
  exit 0
fi

perl -0777 -i -pe '
  my $insert = qq{
    // AUTH_GUARD_RENT_INVOICE_PAY
    // Ensure req.user is populated for this endpoint (jwtVerify must run)
    try {
      if (typeof (req as any).jwtVerify === "function") {
        await (req as any).jwtVerify();
      } else if (typeof (app as any).authenticate === "function") {
        // fallback if project uses app.authenticate
        await (app as any).authenticate(req, reply);
      } else {
        return reply.code(500).send({
          ok: false,
          error: "JWT_NOT_CONFIGURED",
          message: "jwtVerify/app.authenticate not found. Ensure JWT plugin is registered."
        });
      }
    } catch (e) {
      return reply.code(401).send({ ok: false, error: "UNAUTHORIZED", message: "Unauthorized" });
    }
  };

  # Match ANY rent-invoices pay route, even if it has an options object before the handler
  # Examples matched:
  # app.post("/v1/rent-invoices/:id/pay", async (req, reply) => {
  # app.post("/v1/rent-invoices/:id/pay", { preHandler: ... }, async (req, reply) => {
  s{
    (app\.post\(\s*["\x27]\/v1\/rent-invoices\/:[^\/]+\/pay["\x27]\s*,.*?async\s*\(\s*req\b[^\)]*\)\s*=>\s*\{\n)
  }{$1$insert\n}sx
  or die "Could not locate the /v1/rent-invoices/:x/pay route in rent_invoices.ts\n";
' "$FILE"

echo "✅ Patched: $FILE"
echo "➡️ Restart: npm run dev"
