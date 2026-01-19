#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE="$ROOT/src/services/purchase_refunds.service.ts"

[ -f "$FILE" ] || { echo "❌ Not found: $FILE"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$ROOT/scripts/.bak"
cp "$FILE" "$ROOT/scripts/.bak/purchase_refunds.service.ts.bak.$TS"
echo "✅ backup -> scripts/.bak/purchase_refunds.service.ts.bak.$TS"

# Patch: for each upsertRefundMilestones(client, { ... }) call,
# if it does NOT contain "lastPaymentId:", insert it right after purchaseId.
perl -0777 -i -pe '
  s{
    upsertRefundMilestones\(
      \s*client\s*,\s*\{
      ([\s\S]*?)
      \}\s*\)
  }{
    my $body = $1;

    # If already present, leave as-is.
    if ($body =~ /lastPaymentId\s*:/) {
      "upsertRefundMilestones(client, {" . $body . "})";
    } else {
      # Insert after the purchaseId line.
      $body =~ s{
        (\n\s*purchaseId\s*:\s*[^\n]+;\s*|\n\s*purchaseId\s*:\s*[^\n]+,\s*)
      }{
        $1 . "\n      lastPaymentId: purchase.last_payment_id ?? null,"
      }ex
      or die "PATCH_FAIL: could not find purchaseId line inside upsertRefundMilestones call";

      "upsertRefundMilestones(client, {" . $body . "})";
    }
  }gex;
' "$FILE"

# Sanity: ensure we now have lastPaymentId passed at least once in calls
grep -n "upsertRefundMilestones(client" -n "$FILE" >/dev/null || { echo "❌ sanity failed: no upsertRefundMilestones calls found"; exit 1; }
grep -n "lastPaymentId:" "$FILE" >/dev/null || { echo "❌ sanity failed: lastPaymentId not found after patch"; exit 1; }

echo "🔎 Typecheck..."
npx -y tsc -p "$ROOT/tsconfig.json" --noEmit
echo "✅ FIXED: $FILE"

echo ""
echo "NEXT:"
echo "  1) restart dev server so tsx reloads:"
echo "     npm run dev"
