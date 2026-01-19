#!/usr/bin/env bash
set -euo pipefail

echo "== Fix rent invoice PAY flow (service + route) =="

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVICE="$ROOT/src/services/rent_invoices.service.ts"
ROUTE="$ROOT/src/routes/rent_invoices.ts"

ts="$(date +%Y%m%d_%H%M%S)"

if [ ! -f "$SERVICE" ]; then
  echo "ERROR: Missing $SERVICE"
  exit 1
fi
if [ ! -f "$ROUTE" ]; then
  echo "ERROR: Missing $ROUTE"
  exit 1
fi

mkdir -p "$ROOT/scripts/.bak"
cp -f "$SERVICE" "$ROOT/scripts/.bak/rent_invoices.service.ts.bak.$ts"
cp -f "$ROUTE" "$ROOT/scripts/.bak/rent_invoices.ts.bak.$ts"
echo "✅ Backups saved to scripts/.bak/"

# 1) Patch SERVICE: payRentInvoice() -> returns {row,reused}
perl -0777 -i -pe '
  if ($_ =~ /PAY_RETURNS_REUSED_MARKER/) { print STDERR "✅ Service already patched.\n"; exit 0; }

  my $replacement = qq{
\n// PAY_RETURNS_REUSED_MARKER
export async function payRentInvoice(
  client: PoolClient,
  args: {
    invoiceId: string;
    paymentMethod: string;
    amount?: number | null;
  }
): Promise<{ row: RentInvoiceRow; reused: boolean }> {
  const invRes = await client.query<RentInvoiceRow>(
    `
    SELECT ${RENT_INVOICE_SELECT}
    FROM public.rent_invoices
    WHERE id = $1::uuid
      AND deleted_at IS NULL
    LIMIT 1;
    `,
    [args.invoiceId]
  );

  const invoice = invRes.rows[0];
  if (!invoice) {
    const e: any = new Error("Invoice not found");
    e.code = "INVOICE_NOT_FOUND";
    throw e;
  }

  if (invoice.status === "paid") return { row: invoice, reused: true };

  const total = Number(invoice.total_amount);
  const amount = typeof args.amount === "number" ? args.amount : total;

  if (Number(amount) !== Number(total)) {
    const e: any = new Error(`Payment.amount (${amount}) must equal invoice.total_amount (${invoice.total_amount})`);
    e.code = "AMOUNT_MISMATCH";
    throw e;
  }

  const updRes = await client.query<RentInvoiceRow>(
    `
    UPDATE public.rent_invoices
    SET
      status = \'paid\'::invoice_status,
      paid_amount = $2::numeric,
      paid_at = NOW()
    WHERE id = $1::uuid
      AND deleted_at IS NULL
    RETURNING ${RENT_INVOICE_SELECT};
    `,
    [args.invoiceId, amount]
  );

  return { row: updRes.rows[0]!, reused: false };
}
};

  my $count = 0;
  $_ =~ s{
    export\s+async\s+function\s+payRentInvoice\s*\(
      .*?
    \)\s*:\s*Promise<[^>]*>\s*\{
      .*?
    \n\}
  }{$replacement}sx and $count++;

  if ($count == 0) {
    die "Could not locate payRentInvoice() in $ARGV.\n";
  }
' "$SERVICE"

echo "✅ Patched: src/services/rent_invoices.service.ts"

# 2) Patch ROUTE: add AuthReq type if missing
if ! grep -q "type AuthReq" "$ROUTE"; then
  perl -0777 -i -pe '
    my $block = qq{

type AuthReq = {
  user?: { sub?: string; role?: string };
  jwtVerify?: () => Promise<void>;
  params?: any;
  body?: any;
  query?: any;
};
};

    s{(\nimport[^\n]*;\n(?:import[^\n]*;\n)*)}{$1$block\n}sx
      or die "Could not insert AuthReq type after imports.\n";
  ' "$ROUTE"
  echo "✅ Added AuthReq typing"
fi

# 3) Replace PAY route handler
perl -0777 -i -pe '
  if ($_ =~ /PAY_ROUTE_DB_ROLE_MARKER/) { print STDERR "✅ PAY route already patched.\n"; exit 0; }

  my $replacement = qq{
\n  // PAY_ROUTE_DB_ROLE_MARKER
  app.post("/v1/rent-invoices/:id/pay", async (req, reply) => {
    const authResp = await ensureAuth(app, req, reply);
    if (authResp) return authResp;

    const anyReq = req as unknown as AuthReq;

    const userId = anyReq.user?.sub;
    if (!userId) {
      return reply.code(401).send({
        ok: false,
        error: "USER_ID_MISSING",
        message: "Missing authenticated user id (req.user.sub)",
      });
    }

    const pgAny: any = (app as any).pg;
    if (!pgAny?.connect) {
      return reply.code(500).send({
        ok: false,
        error: "PG_NOT_CONFIGURED",
        message: "Fastify pg plugin not found at app.pg",
      });
    }

    const params = z.object({ id: z.string().uuid() }).parse(anyReq.params);
    const body = PayRentInvoiceBodySchema.parse(anyReq.body);

    const client = await pgAny.connect();
    try {
      const roleRes = await client.query<{ role: string }>(
        "select role from public.users where id = $1::uuid limit 1;",
        [userId]
      );
      const dbRole = roleRes.rows[0]?.role;

      if (dbRole !== "admin") {
        return reply.code(403).send({
          ok: false,
          error: "FORBIDDEN",
          message: "Admin only for now (policy requires admin or service role).",
        });
      }

      anyReq.user = anyReq.user ?? {};
      anyReq.user.role = "admin";

      await client.query("BEGIN");

      const { row, reused } = await payRentInvoice(client, {
        invoiceId: params.id,
        paymentMethod: body.paymentMethod,
        amount: body.amount,
      });

      await client.query("COMMIT");
      return reply.send({ ok: true, alreadyPaid: reused, data: row });
    } catch (err: any) {
      try { await client.query("ROLLBACK"); } catch {}
      return reply.code(500).send({
        ok: false,
        error: err?.code ?? "INTERNAL_ERROR",
        message: err?.message ?? String(err),
      });
    } finally {
      client.release();
    }
  });
};

  my $count = 0;
  $_ =~ s{
    \n\s*app\.post\(\s*["\x27]\/v1\/rent-invoices\/:id\/pay["\x27]\s*,\s*async\s*\(\s*req\s*,\s*reply\s*\)\s*=>\s*\{
      .*?
    \n\s*\}\);\s*
  }{$replacement}sx and $count++;

  if ($count == 0) {
    die "Could not locate PAY route handler in $ARGV.\n";
  }
' "$ROUTE"

echo "✅ Patched: src/routes/rent_invoices.ts (PAY route)"

echo ""
echo "== Done =="
echo "➡️ Restart server: npm run dev"
