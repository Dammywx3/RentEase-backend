#!/usr/bin/env bash
set -euo pipefail

trap 'echo; echo "❌ FAILED at line $LINENO"; echo "Last command: $BASH_COMMAND"; echo; exit 1' ERR

echo "== Rent Invoice PAY full fix (routes + registrations) =="

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TS="$(date +%Y%m%d_%H%M%S)"
echo "ROOT=$ROOT"

mkdir -p "$ROOT/scripts/.bak"

backup() {
  local f="$1"
  if [ -f "$f" ]; then
    cp -a "$f" "$ROOT/scripts/.bak/$(basename "$f").bak.$TS"
    echo "🧾 backup: $f -> scripts/.bak/$(basename "$f").bak.$TS"
  else
    echo "⚠️  skip backup (missing): $f"
  fi
}

FILE_RENT="$ROOT/src/routes/rent_invoices.ts"
FILE_INDEX="$ROOT/src/routes/index.ts"
FILE_SERVER="$ROOT/src/server.ts"

backup "$FILE_RENT"
backup "$FILE_INDEX"
backup "$FILE_SERVER"

if [ ! -f "$FILE_RENT" ]; then
  echo "❌ ERROR: $FILE_RENT not found"
  exit 1
fi

cat > "$FILE_RENT" <<'TS'
import type { FastifyInstance } from "fastify";
import { z } from "zod";
import {
  generateRentInvoiceForTenancy,
  getRentInvoices,
  payRentInvoice,
} from "../services/rent_invoices.service.js";
import {
  GenerateRentInvoiceBodySchema,
  ListRentInvoicesQuerySchema,
  PayRentInvoiceBodySchema,
} from "../schemas/rent_invoices.schema.js";

async function ensureAuth(app: FastifyInstance, req: any, reply: any) {
  try {
    if (typeof req?.jwtVerify === "function") {
      await req.jwtVerify();
      return;
    }
    if (typeof (app as any).authenticate === "function") {
      await (app as any).authenticate(req, reply);
      return;
    }
    return reply.code(500).send({
      ok: false,
      error: "JWT_NOT_CONFIGURED",
      message: "jwtVerify/app.authenticate not found. Ensure JWT plugin is registered.",
    });
  } catch {
    return reply.code(401).send({ ok: false, error: "UNAUTHORIZED", message: "Unauthorized" });
  }
}

function requireUserId(req: any) {
  const sub = req?.user?.sub;
  if (!sub) {
    const e: any = new Error("Missing authenticated user id (req.user.sub)");
    e.code = "USER_ID_MISSING";
    throw e;
  }
  return sub as string;
}

export async function rentInvoicesRoutes(app: FastifyInstance) {
  app.post("/v1/tenancies/:id/rent-invoices/generate", async (req, reply) => {
    const authResp = await ensureAuth(app, req, reply);
    if (authResp) return authResp;

    try {
      requireUserId(req);

      const params = z.object({ id: z.string().uuid() }).parse(req.params);
      const body = GenerateRentInvoiceBodySchema.parse(req.body);

      const pgAny: any = (app as any).pg;
      if (!pgAny?.connect) {
        return reply.code(500).send({
          ok: false,
          error: "PG_NOT_CONFIGURED",
          message: "Fastify pg plugin not found at app.pg",
        });
      }

      const client = await pgAny.connect();
      try {
        await client.query("BEGIN");

        const res = await generateRentInvoiceForTenancy(client, {
          tenancyId: params.id,
          periodStart: body.periodStart,
          periodEnd: body.periodEnd,
          dueDate: body.dueDate,
          subtotal: body.subtotal,
          lateFeeAmount: body.lateFeeAmount,
          currency: body.currency,
          status: body.status,
          notes: body.notes,
        });

        await client.query("COMMIT");
        return reply.send({ ok: true, reused: res.reused, data: res.row });
      } catch (err: any) {
        await client.query("ROLLBACK");
        return reply.code(500).send({
          ok: false,
          error: err?.code ?? "INTERNAL_ERROR",
          message: err?.message ?? String(err),
        });
      } finally {
        client.release();
      }
    } catch (err: any) {
      return reply.code(400).send({
        ok: false,
        error: err?.code ?? "BAD_REQUEST",
        message: err?.message ?? String(err),
      });
    }
  });

  app.get("/v1/rent-invoices", async (req, reply) => {
    const authResp = await ensureAuth(app, req, reply);
    if (authResp) return authResp;

    try {
      requireUserId(req);

      const q = ListRentInvoicesQuerySchema.parse((req as any).query);

      const pgAny: any = (app as any).pg;
      if (!pgAny?.connect) {
        return reply.code(500).send({
          ok: false,
          error: "PG_NOT_CONFIGURED",
          message: "Fastify pg plugin not found at app.pg",
        });
      }

      const client = await pgAny.connect();
      try {
        const data = await getRentInvoices(client, {
          limit: q.limit,
          offset: q.offset,
          tenancyId: q.tenancyId,
          tenantId: q.tenantId,
          propertyId: q.propertyId,
          status: q.status,
        });

        return reply.send({ ok: true, data, paging: { limit: q.limit, offset: q.offset } });
      } catch (err: any) {
        return reply.code(500).send({
          ok: false,
          error: err?.code ?? "INTERNAL_ERROR",
          message: err?.message ?? String(err),
        });
      } finally {
        client.release();
      }
    } catch (err: any) {
      return reply.code(400).send({
        ok: false,
        error: err?.code ?? "BAD_REQUEST",
        message: err?.message ?? String(err),
      });
    }
  });

  app.post("/v1/rent-invoices/:id/pay", async (req, reply) => {
    const authResp = await ensureAuth(app, req, reply);
    if (authResp) return authResp;

    const userId = req?.user?.sub;
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

      // make downstream code happy if anything checks req.user.role
      req.user.role = "admin";

      const params = z.object({ id: z.string().uuid() }).parse(req.params);
      const body = PayRentInvoiceBodySchema.parse(req.body);

      await client.query("BEGIN");
      const res = await payRentInvoice(client, {
        invoiceId: params.id,
        paymentMethod: body.paymentMethod,
        amount: body.amount,
      });
      await client.query("COMMIT");

      return reply.send({ ok: true, data: res });
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
}
TS

echo "✅ wrote src/routes/rent_invoices.ts"

# Patch routes/index.ts safely (remove duplicate rentInvoicesRoutes registers)
if [ -f "$FILE_INDEX" ]; then
  perl -0777 -i -pe 's/^\s*await\s+app\.register\(\s*rentInvoicesRoutes\s*\);\s*\n//mg' "$FILE_INDEX"
  if ! grep -q 'app\.register(\s*rentInvoicesRoutes\s*)' "$FILE_INDEX"; then
    perl -0777 -i -pe 's/(export\s+async\s+function\s+registerRoutes\s*\(\s*app:\s*FastifyInstance\s*\)\s*\{\s*\n)/$1  await app.register(rentInvoicesRoutes);\n/s' "$FILE_INDEX"
  fi
  echo "✅ patched src/routes/index.ts"
else
  echo "⚠️ src/routes/index.ts not found (skipped)"
fi

# Patch server.ts: remove direct registerRoutes(app) calls
if [ -f "$FILE_SERVER" ]; then
  perl -0777 -i -pe '
    s/^\s*await\s+await\s+registerRoutes\s*\(\s*app\s*\)\s*;\s*\n//mg;
    s/^\s*await\s+registerRoutes\s*\(\s*app\s*\)\s*;\s*\n//mg;
  ' "$FILE_SERVER"
  echo "✅ patched src/server.ts"
else
  echo "⚠️ src/server.ts not found (skipped)"
fi

echo "✅ Done."
echo "➡️ Restart: npm run dev"
