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
import { payoutRoutes } from "./payouts.routes.js";


export async function routes(app: FastifyInstance) {
  /**
   * ============================================================
   * ROOT (UNVERSIONED) ROUTES
   * ============================================================
   */
  await app.register(demoRoutes, { prefix: "/demo" });
  await app.register(healthRoutes); // /health
  await app.register(webhooksRoutes); // /webhooks/paystack

  // ✅ Register debug routes ONLY ONCE to prevent /debug/debug/*
  await app.register(debugPgCtxRoutes, { prefix: "/debug" });

  /**
   * ============================================================
   * VERSIONED API ROUTES  => /v1/...
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

      // ✅ Purchases (single module owns purchases)
      // ✅ Payouts
      
      //await v1.register(payoutRoutes, { prefix: "/payouts" });
      await v1.register(purchasesRoutes, { prefix: "/purchases" });
      await v1.register(payoutRoutes, { prefix: "/payouts" });
    },
    { prefix: "/v1" }
  );
}

export const registerRoutes = routes;
export default routes;