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
  app.get("/", { preHandler: [app.authenticate] }, async (req: any) => {
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
  app.get("/:id", { preHandler: [app.authenticate] }, async (req: any) => {
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
  app.get("/", { preHandler: [app.authenticate] }, async (req: any) => {
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
  app.patch("/:id", { preHandler: [app.authenticate] }, async (req: any) => {
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
