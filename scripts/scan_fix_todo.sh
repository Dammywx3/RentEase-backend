set -euo pipefail

echo "=== RentEase Fix Scan (TODO list) ==="
echo "PWD: $(pwd)"
echo

echo "---- node / ts ----"
node -v || true
npx tsc -v || true
echo

echo "---- key files exist? ----"
ls -la src/routes/webhooks.ts src/services/paystack_finalize.service.ts src/services/payouts.service.ts src/routes/payouts.routes.ts src/routes/index.ts src/server.ts 2>/dev/null || true
echo

echo "---- scan: purchaseId / reference_id / null issues ----"
rg -n "purchaseId|reference_id|referenceId|asText\\(payment\\.reference_id\\)|payment\\.reference_id" src/services src/routes || true
echo

echo "---- scan: finalizePaystackTransferEvent usage + signature mismatches ----"
rg -n "finalizePaystackTransferEvent|transfer\\.success|transfer\\.failed|transfer\\.reversed" src/services src/routes || true
echo

echo "---- scan: webhooks signature / rawBody hashing / bytesToHash ----"
rg -n "x-paystack-signature|rawBody|getRawBodyBuffer|bytesToHash|createHmac\\(\"sha512\"" src/routes src/services || true
echo

echo "---- scan: setPgContext + actor user id env ----"
rg -n "setPgContext|WEBHOOK_ACTOR_USER_ID|is_admin\\(" src || true
echo

echo "---- scan: purchase escrow hold/release functions ----"
rg -n "purchase_escrow_hold|release_purchase_escrow|escrow_held_amount|escrow_transactions" src/services src/routes || true
echo

echo "---- scan: payments organization_id join logic ----"
rg -n "coalesce\\(pl\\.organization_id, pr\\.organization_id\\)|property_listings pl|properties pr|payments p" src/services src/routes || true
echo

echo "---- TypeScript compile (collect errors) ----"
mkdir -p .tmp
npx tsc -p tsconfig.json --noEmit 2>&1 | tee .tmp/tsc_errors.txt || true
echo

echo "---- TODO LIST (from tsc + scans) ----"
if [ -s .tmp/tsc_errors.txt ]; then
  echo
  echo "### A) TypeScript errors (must fix)"
  cat .tmp/tsc_errors.txt
  echo
else
  echo "✅ No TypeScript compile errors."
  echo
fi

echo "### B) Hotspot checklist (manual review targets)"
cat <<'TXT'
1) paystack_finalize.service.ts
   - Any call that passes payment.reference_id directly -> must guard (string | null).
   - Ensure purchase flow updates purchase paid_amount/payment_status/last_payment_id correctly.
   - Ensure idempotency: don't double-apply for same payment reference.

2) webhooks.ts
   - charge.success path uses resolvePaymentWebhookContext + finalizePaystackChargeSuccess
   - transfer.* path uses resolveTransferWebhookContext + finalizePaystackTransferEvent
   - hashing uses raw bytes (rawBody) with Buffer fallback ✅

3) payouts.service.ts
   - finalizePaystackTransferEvent signature matches how webhooks.ts calls it
     (if webhooks passes actorUserId, payouts.service.ts must accept it or ignore it)
   - processPayoutPaystack uses admin context properly

4) routes/index.ts
   - payoutsRoutes registered only once and under /v1/payouts

5) server.ts
   - rawBody plugin registered before routes ✅
TXT
echo
echo "=== END SCAN ==="
