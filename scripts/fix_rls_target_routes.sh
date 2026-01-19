#!/usr/bin/env bash
set -euo pipefail

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="scripts/backup_routes_$TS"
mkdir -p "$BACKUP_DIR"

files=(
  "src/routes/applications.ts"
  "src/routes/listings.ts"
  "src/routes/viewings.ts"
  "src/routes/me.ts"
  "src/routes/organizations.ts"
)

echo "============================================================"
echo "RentEase: Fix RLS target routes (FULL REWRITE)"
echo "Backup dir: $BACKUP_DIR"
echo "============================================================"

for f in "${files[@]}"; do
  if [[ -f "$f" ]]; then
    cp "$f" "$BACKUP_DIR/$(basename "$f")"
    echo "✅ Backed up: $f"
  else
    echo "❌ Missing: $f (skipping backup)"
  fi
done

echo
echo "------------------------------------------------------------"
echo "Writing fixed route files..."
echo "------------------------------------------------------------"

# ------------------------------------------------------------
# src/routes/applications.ts
# ------------------------------------------------------------
cat > src/routes/applications.ts <<'EOF'
import type { FastifyInstance } from "fastify";
import type { PoolClient } from "pg";

import { withRlsTransaction } from "../db/rls_tx.js";

import {
  createApplication,
  getApplication,
  listAllApplications,
  updateApplication,
} from "../services/applications.service.js";

import {
  createApplicationBodySchema,
  listApplicationsQuerySchema,
  patchApplicationBodySchema,
} from "../schemas/applications.schema.js";

/**
 * INPUT: normalize anything into YYYY-MM-DD (no timezone).
 * - accepts "YYYY-MM-DD"
 * - accepts ISO strings -> trims to date part
 * - accepts Date -> formats using LOCAL date parts (no UTC shift)
 */
function normalizeDateOnlyInput(v: unknown): string | null {
  if (v === null || v === undefined) return null;

  if (v instanceof Date && !Number.isNaN(v.getTime())) {
    const y = v.getFullYear();
    const m = String(v.getMonth() + 1).padStart(2, "0");
    const d = String(v.getDate()).padStart(2, "0");
    return `${y}-${m}-${d}`;
  }

  if (typeof v === "string") {
    if (v.includes("T")) return v.slice(0, 10);
    return v;
  }

  return null;
}

/**
 * OUTPUT: force move_in_date to YYYY-MM-DD consistently.
 * If pg gives Date object, format with LOCAL date parts to avoid -1 day shift.
 */
function toDateOnlyOutput(v: unknown): string | null {
  if (v === null || v === undefined) return null;

  if (v instanceof Date && !Number.isNaN(v.getTime())) {
    const y = v.getFullYear();
    const m = String(v.getMonth() + 1).padStart(2, "0");
    const d = String(v.getDate()).padStart(2, "0");
    return `${y}-${m}-${d}`;
  }

  if (typeof v === "string") {
    if (v.includes("T")) return v.slice(0, 10);
    return v;
  }

  return null;
}

function normalizeApplicationRow(row: any) {
  if (!row) return row;
  return {
    ...row,
    move_in_date: toDateOnlyOutput(row.move_in_date),
  };
}

function normalizeApplicationRows(rows: any[]) {
  return rows.map(normalizeApplicationRow);
}

function getCtx(req: any) {
  const userId = String(req?.user?.userId ?? "").trim();
  const organizationId = String(req?.orgId ?? "").trim();
  const role = (req?.user?.role ?? null) as any;
  return { userId, organizationId, role };
}

export async function applicationRoutes(app: FastifyInstance) {
  // LIST
  app.get("/applications", { preHandler: [app.authenticate] }, async (req: any) => {
    const q = listApplicationsQuerySchema.parse(req.query ?? {});
    const ctx = getCtx(req);

    const data = await withRlsTransaction(
      {
        userId: ctx.userId,
        organizationId: ctx.organizationId,
        role: ctx.role,
        eventNote: "applications:list",
      },
      async (client: PoolClient) => {
        const rows = await listAllApplications(client, {
          limit: q.limit,
          offset: q.offset,
          listing_id: q.listingId,
          property_id: q.propertyId,
          applicant_id: q.applicantId,
          status: q.status ?? undefined,
        });

        return normalizeApplicationRows(rows as any[]);
      }
    );

    return { ok: true, data, paging: { limit: q.limit, offset: q.offset } };
  });

  // GET ONE
  app.get("/applications/:id", { preHandler: [app.authenticate] }, async (req: any) => {
    const { id } = req.params as any;
    const ctx = getCtx(req);

    const data = await withRlsTransaction(
      {
        userId: ctx.userId,
        organizationId: ctx.organizationId,
        role: ctx.role,
        eventNote: `applications:get:${String(id)}`,
      },
      async (client: PoolClient) => {
        const row = await getApplication(client, String(id));
        return normalizeApplicationRow(row);
      }
    );

    return { ok: true, data };
  });

  // CREATE
  app.post("/applications", { preHandler: [app.authenticate] }, async (req: any) => {
    const body = createApplicationBodySchema.parse(req.body ?? {});
    const ctx = getCtx(req);

    const allowStatus = req.user?.role === "admin";
    const status = allowStatus ? (body.status ?? undefined) : undefined;

    const data = await withRlsTransaction(
      {
        userId: ctx.userId,
        organizationId: ctx.organizationId,
        role: ctx.role,
        eventNote: "applications:create",
      },
      async (client: PoolClient) => {
        const row = await createApplication(
          client,
          { userId: ctx.userId },
          {
            listing_id: body.listingId,
            property_id: body.propertyId,
            message: body.message ?? null,
            monthly_income: body.monthlyIncome ?? null,
            move_in_date: normalizeDateOnlyInput(body.moveInDate),
            status,
          }
        );

        return normalizeApplicationRow(row);
      }
    );

    return { ok: true, data };
  });

  // PATCH
  app.patch("/applications/:id", { preHandler: [app.authenticate] }, async (req: any) => {
    const { id } = req.params as any;
    const body = patchApplicationBodySchema.parse(req.body ?? {});
    const ctx = getCtx(req);

    const patch: any = {};
    if (body.status !== undefined) patch.status = body.status;
    if (body.message !== undefined) patch.message = body.message;
    if (body.monthlyIncome !== undefined) patch.monthly_income = body.monthlyIncome;

    if (body.moveInDate !== undefined) {
      patch.move_in_date = normalizeDateOnlyInput(body.moveInDate);
    }

    const data = await withRlsTransaction(
      {
        userId: ctx.userId,
        organizationId: ctx.organizationId,
        role: ctx.role,
        eventNote: `applications:patch:${String(id)}`,
      },
      async (client: PoolClient) => {
        const row = await updateApplication(client, String(id), patch);
        return normalizeApplicationRow(row);
      }
    );

    return { ok: true, data };
  });
}
EOF

# ------------------------------------------------------------
# src/routes/listings.ts
# ------------------------------------------------------------
cat > src/routes/listings.ts <<'EOF'
import type { FastifyInstance } from "fastify";
import type { PoolClient } from "pg";

import { withRlsTransaction } from "../db/rls_tx.js";

import {
  createListing,
  getListing,
  listAllListings,
  updateListing,
} from "../services/listings.service.js";

import type { CreateListingBody, PatchListingBody } from "../schemas/listings.schema.js";

function getCtx(req: any) {
  const userId = String(req?.user?.userId ?? "").trim();
  const organizationId = String(req?.orgId ?? "").trim();
  const role = (req?.user?.role ?? null) as any;
  return { userId, organizationId, role };
}

export async function listingRoutes(app: FastifyInstance) {
  // LIST
  app.get("/listings", { preHandler: [app.authenticate] }, async (req: any) => {
    const q = req.query as any;
    const limit = Math.max(1, Math.min(100, Number(q.limit ?? 10)));
    const offset = Math.max(0, Number(q.offset ?? 0));

    const ctx = getCtx(req);

    const data = await withRlsTransaction(
      { userId: ctx.userId, organizationId: ctx.organizationId, role: ctx.role, eventNote: "listings:list" },
      async (client: PoolClient) => listAllListings(client, { limit, offset })
    );

    return { ok: true, data, paging: { limit, offset } };
  });

  // GET ONE
  app.get("/listings/:id", { preHandler: [app.authenticate] }, async (req: any) => {
    const { id } = req.params as any;
    const ctx = getCtx(req);

    const data = await withRlsTransaction(
      { userId: ctx.userId, organizationId: ctx.organizationId, role: ctx.role, eventNote: `listings:get:${String(id)}` },
      async (client: PoolClient) => getListing(client, id)
    );

    return { ok: true, data };
  });

  // CREATE
  app.post("/listings", { preHandler: [app.authenticate] }, async (req: any, reply) => {
    const body = req.body as CreateListingBody;

    // app-level checks to avoid DB trigger errors
    if (!body.propertyId) return reply.code(400).send({ ok: false, message: "propertyId is required" });
    if (!body.kind) return reply.code(400).send({ ok: false, message: "kind is required" });
    if (!body.payeeUserId) return reply.code(400).send({ ok: false, message: "payeeUserId is required" });
    if (typeof body.basePrice !== "number" || body.basePrice <= 0) {
      return reply.code(400).send({ ok: false, message: "basePrice must be > 0" });
    }
    if (typeof body.listedPrice !== "number" || body.listedPrice <= 0) {
      return reply.code(400).send({ ok: false, message: "listedPrice must be > 0" });
    }

    // schema trigger expects agent_id for agent_direct (and usually agent_partner too)
    if ((body.kind === "agent_direct" || body.kind === "agent_partner") && !body.agentId) {
      return reply.code(400).send({ ok: false, message: `${body.kind} listing requires agentId` });
    }

    const ctx = getCtx(req);

    const data = await withRlsTransaction(
      { userId: ctx.userId, organizationId: ctx.organizationId, role: ctx.role, eventNote: "listings:create" },
      async (client: PoolClient) => {
        return createListing(client, {
          property_id: body.propertyId,
          kind: body.kind,

          // omit status if not provided so DB default 'draft' applies
          status: typeof body.status === "undefined" ? undefined : body.status,

          agent_id: body.agentId ?? null,
          payee_user_id: body.payeeUserId,

          base_price: body.basePrice,
          listed_price: body.listedPrice,

          agent_commission_percent: body.agentCommissionPercent ?? null,
          requires_owner_approval: body.requiresOwnerApproval ?? null,
          is_public: body.isPublic ?? null,
          public_note: body.publicNote ?? null,
        });
      }
    );

    return { ok: true, data };
  });

  // PATCH
  app.patch("/listings/:id", { preHandler: [app.authenticate] }, async (req: any) => {
    const { id } = req.params as any;
    const body = req.body as PatchListingBody;

    const ctx = getCtx(req);

    const data = await withRlsTransaction(
      { userId: ctx.userId, organizationId: ctx.organizationId, role: ctx.role, eventNote: `listings:patch:${String(id)}` },
      async (client: PoolClient) => {
        return updateListing(client, id, {
          status: body.status ?? undefined,
          agent_id: body.agentId ?? undefined,
          payee_user_id: body.payeeUserId ?? undefined,
          base_price: body.basePrice ?? undefined,
          listed_price: body.listedPrice ?? undefined,
          agent_commission_percent: body.agentCommissionPercent ?? undefined,
          requires_owner_approval: body.requiresOwnerApproval ?? undefined,
          is_public: body.isPublic ?? undefined,
          public_note: body.publicNote ?? undefined,
        });
      }
    );

    return { ok: true, data };
  });
}
EOF

# ------------------------------------------------------------
# src/routes/viewings.ts
# ------------------------------------------------------------
cat > src/routes/viewings.ts <<'EOF'
import type { FastifyInstance } from "fastify";
import type { PoolClient } from "pg";

import { withRlsTransaction } from "../db/rls_tx.js";

import { createViewing, getViewing, listAllViewings, updateViewing } from "../services/viewings.service.js";
import { createViewingBodySchema, listViewingsQuerySchema, patchViewingBodySchema } from "../schemas/viewings.schema.js";

function getCtx(req: any) {
  const userId = String(req?.user?.userId ?? "").trim();
  const organizationId = String(req?.orgId ?? "").trim();
  const role = (req?.user?.role ?? null) as any;
  return { userId, organizationId, role };
}

export async function viewingRoutes(app: FastifyInstance) {
  app.get("/viewings", { preHandler: [app.authenticate] }, async (req: any) => {
    const q = listViewingsQuerySchema.parse(req.query ?? {});
    const ctx = getCtx(req);

    const data = await withRlsTransaction(
      { userId: ctx.userId, organizationId: ctx.organizationId, role: ctx.role, eventNote: "viewings:list" },
      async (client: PoolClient) => {
        return listAllViewings(client, {
          limit: q.limit,
          offset: q.offset,
          listing_id: q.listingId,
          property_id: q.propertyId,
          tenant_id: q.tenantId,
          status: q.status ?? undefined,
        });
      }
    );

    return { ok: true, data, paging: { limit: q.limit, offset: q.offset } };
  });

  app.get("/viewings/:id", { preHandler: [app.authenticate] }, async (req: any) => {
    const { id } = req.params as any;
    const ctx = getCtx(req);

    const data = await withRlsTransaction(
      { userId: ctx.userId, organizationId: ctx.organizationId, role: ctx.role, eventNote: `viewings:get:${String(id)}` },
      async (client: PoolClient) => {
        return getViewing(client, String(id));
      }
    );

    return { ok: true, data };
  });

  app.post("/viewings", { preHandler: [app.authenticate] }, async (req: any) => {
    const body = createViewingBodySchema.parse(req.body ?? {});
    const ctx = getCtx(req);

    const allowStatus = req.user?.role === "admin";
    const status = allowStatus ? (body.status ?? undefined) : undefined;

    const data = await withRlsTransaction(
      { userId: ctx.userId, organizationId: ctx.organizationId, role: ctx.role, eventNote: "viewings:create" },
      async (client: PoolClient) => {
        return createViewing(
          client,
          { userId: ctx.userId },
          {
            listing_id: body.listingId,
            property_id: body.propertyId,
            scheduled_at: body.scheduledAt,
            view_mode: body.viewMode ?? undefined,
            notes: body.notes ?? null,
            status,
          }
        );
      }
    );

    return { ok: true, data };
  });

  app.patch("/viewings/:id", { preHandler: [app.authenticate] }, async (req: any) => {
    const { id } = req.params as any;
    const body = patchViewingBodySchema.parse(req.body ?? {});
    const ctx = getCtx(req);

    const patch: any = {};
    if (body.scheduledAt !== undefined) patch.scheduled_at = body.scheduledAt;
    if (body.viewMode !== undefined) patch.view_mode = body.viewMode;
    if (body.notes !== undefined) patch.notes = body.notes;

    if (body.status !== undefined) {
      if (req.user?.role !== "admin") return { ok: false, error: "FORBIDDEN", message: "Only admin can change viewing status." };
      patch.status = body.status;
    }

    const data = await withRlsTransaction(
      { userId: ctx.userId, organizationId: ctx.organizationId, role: ctx.role, eventNote: `viewings:patch:${String(id)}` },
      async (client: PoolClient) => {
        return updateViewing(client, String(id), patch);
      }
    );

    return { ok: true, data };
  });
}
EOF

# ------------------------------------------------------------
# src/routes/me.ts
# ------------------------------------------------------------
cat > src/routes/me.ts <<'EOF'
import type { FastifyInstance } from "fastify";
import type { PoolClient } from "pg";

import { withRlsTransaction } from "../db/rls_tx.js";

function getCtx(req: any) {
  const userId = String(req?.user?.userId ?? "").trim();
  const organizationId = String(req?.orgId ?? "").trim();
  const role = (req?.user?.role ?? null) as any;
  return { userId, organizationId, role };
}

export async function meRoutes(app: FastifyInstance) {
  app.get("/me", { preHandler: [app.authenticate] }, async (req: any) => {
    const ctx = getCtx(req);

    const me = await withRlsTransaction(
      { userId: ctx.userId, organizationId: ctx.organizationId, role: ctx.role, eventNote: "me:get" },
      async (client: PoolClient) => {
        const { rows } = await client.query(
          `
          SELECT
            id,
            organization_id,
            full_name,
            email,
            phone,
            role,
            verified_status,
            created_at,
            updated_at
          FROM users
          WHERE id = $1
          LIMIT 1
          `,
          [ctx.userId]
        );

        return rows[0] ?? null;
      }
    );

    return { ok: true, data: me };
  });
}
EOF

# ------------------------------------------------------------
# src/routes/organizations.ts
# ------------------------------------------------------------
cat > src/routes/organizations.ts <<'EOF'
import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { PoolClient } from "pg";

import { withRlsTransaction } from "../db/rls_tx.js";

const paramsSchema = z.object({
  id: z.string().uuid(),
});

const updateBodySchema = z.object({
  name: z.string().min(2).max(120),
});

type OrgRow = {
  id: string;
  name: string;
  created_at?: string;
  updated_at?: string;
};

function getCtx(req: any) {
  const userId = String(req?.user?.userId ?? "").trim();
  const organizationId = String(req?.orgId ?? "").trim();
  const role = (req?.user?.role ?? null) as any;
  return { userId, organizationId, role };
}

async function getOrg(client: PoolClient, id: string): Promise<OrgRow | null> {
  const { rows } = await client.query<OrgRow>(
    `
    SELECT id, name, created_at, updated_at
    FROM organizations
    WHERE id = $1
    LIMIT 1
    `,
    [id]
  );
  return rows[0] ?? null;
}

async function updateOrgName(client: PoolClient, id: string, name: string): Promise<OrgRow | null> {
  const { rows } = await client.query<OrgRow>(
    `
    UPDATE organizations
    SET name = $2, updated_at = now()
    WHERE id = $1
    RETURNING id, name, created_at, updated_at
    `,
    [id, name]
  );
  return rows[0] ?? null;
}

export async function organizationRoutes(app: FastifyInstance) {
  // GET /v1/organizations/:id
  app.get("/organizations/:id", { preHandler: [app.authenticate] }, async (req: any) => {
    const { id } = paramsSchema.parse((req as any).params);
    const ctx = getCtx(req);

    const org = await withRlsTransaction(
      { userId: ctx.userId, organizationId: ctx.organizationId, role: ctx.role, eventNote: `org:get:${id}` },
      async (client) => getOrg(client, id)
    );

    if (!org) return { ok: false, error: "NOT_FOUND", message: "Organization not found" };
    return { ok: true, data: org };
  });

  // PUT /v1/organizations/:id
  app.put("/organizations/:id", { preHandler: [app.authenticate] }, async (req: any) => {
    const { id } = paramsSchema.parse((req as any).params);
    const body = updateBodySchema.parse((req as any).body);
    const ctx = getCtx(req);

    const updated = await withRlsTransaction(
      { userId: ctx.userId, organizationId: ctx.organizationId, role: ctx.role, eventNote: `org:put:${id}` },
      async (client) => updateOrgName(client, id, body.name)
    );

    if (!updated) return { ok: false, error: "NOT_FOUND", message: "Organization not found" };
    return { ok: true, data: updated };
  });
}
EOF

echo
echo "============================================================"
echo "✅ Done writing fixed files."
echo "Backups saved in: $BACKUP_DIR"
echo
echo "Next run:"
echo "  npm run build"
echo "  npm run dev"
echo "============================================================"
