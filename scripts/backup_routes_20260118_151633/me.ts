import type { FastifyInstance } from "fastify";
import type { PoolClient } from "pg";
import { withRlsTransaction } from "../config/database.js";

export async function meRoutes(app: FastifyInstance) {
  app.get("/me", { preHandler: [app.authenticate] }, async (req) => {
    const userId = req.user.sub;
    const organizationId = req.user.org;

    const me = await withRlsTransaction(
      { userId, organizationId },
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
          [userId]
        );

        return rows[0] ?? null;
      }
    );

    return { ok: true, data: me };
  });
}
