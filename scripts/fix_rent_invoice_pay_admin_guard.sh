#!/usr/bin/env bash
set -euo pipefail

echo "== Patch PAY route: enforce admin via DB role (insert guard) =="

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILE="$ROOT/src/routes/rent_invoices.ts"

if [ ! -f "$FILE" ]; then
  echo "ERROR: $FILE not found"
  exit 1
fi

if grep -q "PAY_ADMIN_GUARD_DB_ROLE" "$FILE"; then
  echo "✅ Already patched (marker found)."
  exit 0
fi

perl -0777 -i -pe '
  my $guard = qq{
    // PAY_ADMIN_GUARD_DB_ROLE
    // Admin-only for now: enforce based on DB user role (not JWT claims)
    const userId = (req as any).user?.sub;
    if (!userId) {
      return reply.code(401).send({ ok: false, error: "UNAUTHORIZED", message: "Unauthorized" });
    }

    // Ensure we have a pg client available (this route uses app.pg in this codebase)
    const pgAny: any = (app as any).pg;
    if (!pgAny?.connect) {
      return reply.code(500).send({ ok: false, error: "PG_NOT_CONFIGURED", message: "Fastify pg plugin not found at app.pg" });
    }

    const client = await pgAny.connect();
    try {
      const roleRes = await client.query<{ role: string }>(
        "select role from public.users where id = \$1::uuid limit 1;",
        [userId]
      );
      const dbRole = roleRes.rows[0]?.role;

      if (dbRole !== "admin") {
        return reply.code(403).send({
          ok: false,
          error: "FORBIDDEN",
          message: "Admin only for now (policy requires admin or service role)."
        });
      }
    } finally {
      client.release();
    }
  };

  # Insert the guard right after the pay route handler begins.
  # We match: app.post("/v1/rent-invoices/:id/pay", async (req, reply) => {
  s{
    (app\.post\(\s*["\x27]\/v1\/rent-invoices\/:id\/pay["\x27]\s*,\s*async\s*\(\s*req\s*,\s*reply\s*\)\s*=>\s*\{\s*\n)
  }{$1$guard\n}sx
  or die "Could not locate pay route signature: app.post(\"/v1/rent-invoices/:id/pay\", async (req, reply) => { ... }\n";
' "$FILE"

echo "✅ Patched PAY route in: $FILE"
echo "➡️ Restart: npm run dev"
