// src/routes/index.ts
import type { FastifyInstance } from "fastify";

import { demoRoutes } from "./demo.js";
import { healthRoutes } from "./health.js";
import { webhooksRoutes } from "./webhooks.js";
import { debugPgCtxRoutes } from "./debug_pgctx.js";

import { authRoutes } from "./auth.js";
import { meRoutes } from "./me.js";
import { organizationRoutes } from "./organizations.js";

import { propertyRoutes } from "./properties.js";
import { listingRoutes } from "./listings.js";
import { applicationRoutes } from "./applications.js";
import { viewingRoutes } from "./viewings.js";
import { tenancyRoutes } from "./tenancies.js";

import { rentInvoicesRoutes } from "./rent_invoices.js";
import { paymentsRoutes } from "./payments.js";

import { purchasesRoutes } from "./purchases.routes.js";
import { purchaseCloseRoutes } from "./purchase_close.js";
import { purchaseEscrowRoutes } from "./purchase_escrow.js";

export async function routes(app: FastifyInstance) {
  /**
   * ============================================================
   * ROOT (UNVERSIONED) ROUTES
   * These should stay stable and not be under /v1
   * ============================================================
   */
  await app.register(demoRoutes, { prefix: "/demo" });
  await app.register(healthRoutes); // e.g. /health
  await app.register(webhooksRoutes); // e.g. /webhooks/paystack
  await app.register(debugPgCtxRoutes, { prefix: "/debug" }); 

  /**
   * ============================================================
   * VERSIONED API ROUTES
   * Everything here becomes /v1/...
   * ============================================================
   */
  await app.register(
    async function v1(v1) {
      // Auth
      await v1.register(authRoutes, { prefix: "/auth" });

      // Core identity/org
      await v1.register(meRoutes, { prefix: "/me" });
      await v1.register(organizationRoutes, { prefix: "/organizations" });

      // Properties + listings flow
      await v1.register(propertyRoutes, { prefix: "/properties" });
      await v1.register(listingRoutes, { prefix: "/listings" });
      await v1.register(applicationRoutes, { prefix: "/applications" });
      await v1.register(viewingRoutes, { prefix: "/viewings" });
      await v1.register(tenancyRoutes, { prefix: "/tenancies" });

      // Billing
      await v1.register(rentInvoicesRoutes, { prefix: "/rent-invoices" });
      await v1.register(paymentsRoutes, { prefix: "/payments" });

      // Purchases
      await v1.register(purchasesRoutes, { prefix: "/purchases" });

      /**
       * If these are sub-modules under purchases, keep them under the same prefix
       * and make sure inside those files the paths are "/" or "/:id/close" etc.
       */
      await v1.register(purchaseCloseRoutes, { prefix: "/purchases" });
      await v1.register(purchaseEscrowRoutes, { prefix: "/purchases" });

      // DB ping (if you have it in routes somewhere)
      // Example: if dbPingRoutes exists, register here:
      // await v1.register(dbPingRoutes, { prefix: "/db" });
    },
    { prefix: "/v1" }
  );
}

// Backwards-compatible alias (src/server.ts imports { registerRoutes })
export const registerRoutes = routes;
export default routes;