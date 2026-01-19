#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
echo "ROOT=$ROOT"

# 1) Find a routes file that already has rent-invoice pay logic
ROUTE_FILE="$(
  (grep -RIl --exclude-dir=node_modules --exclude-dir=dist -E "rent-invoices.*/pay|/rent-invoices/.*/pay|rent_invoices.*pay" src/routes src 2>/dev/null || true) | head -n 1
)"

if [[ -z "${ROUTE_FILE:-}" ]]; then
  echo "❌ Could not find a routes file containing the rent invoice pay endpoint."
  echo "   Run: grep -RIn \"rent-invoices\" src/routes src | head -n 50"
  exit 1
fi

echo "✅ Using ROUTE_FILE=$ROUTE_FILE"

# 2) Patch the file using python for safe text editing
python3 - <<'PY'
import os, re

route_file = os.environ["ROUTE_FILE"]
txt = open(route_file, "r", encoding="utf-8").read()

# If already patched, exit clean
if "payPropertyPurchase" in txt and "purchases" in txt and "/pay" in txt:
    print("✅ Already patched (purchase pay route appears present).")
    raise SystemExit(0)

# Decide whether this file uses /v1 prefix inside route strings
# We mimic the rent invoice style we find in the file.
uses_v1_prefix = bool(re.search(r"['\"]/v1/rent-invoices", txt))
route_path = "/v1/purchases/:purchaseId/pay" if uses_v1_prefix else "/purchases/:purchaseId/pay"

# Determine whether Router variable exists (router.post) or app.post
uses_router = bool(re.search(r"\brouter\.(post|get|put|delete)\s*\(", txt))
handler_target = "router" if uses_router else "app"

# Ensure import for payPropertyPurchase exists
if "payPropertyPurchase" not in txt:
    # Insert after other imports near top
    # Prefer placing after last import line
    m = list(re.finditer(r"^import .*?$", txt, flags=re.MULTILINE))
    if m:
        insert_at = m[-1].end()
        txt = txt[:insert_at] + "\nimport { payPropertyPurchase } from \"../services/purchase_payments.service.js\";\n" + txt[insert_at:]
    else:
        # fallback: add to very top
        txt = "import { payPropertyPurchase } from \"../services/purchase_payments.service.js\";\n" + txt

# Ensure pool exists or import it
# We try to detect 'pool' usage; if not present, we add an import
has_pool_symbol = bool(re.search(r"\bpool\b", txt))
has_pool_import = bool(re.search(r"import\s*\{\s*pool\s*\}\s*from\s*[\"']\.\./config/database\.js[\"']", txt))

if (not has_pool_import) and (not has_pool_symbol):
    # Add import for pool after imports
    m = list(re.finditer(r"^import .*?$", txt, flags=re.MULTILINE))
    if m:
        insert_at = m[-1].end()
        txt = txt[:insert_at] + "\nimport { pool } from \"../config/database.js\";\n" + txt[insert_at:]
    else:
        txt = "import { pool } from \"../config/database.js\";\n" + txt

# Avoid duplicate route if already present (string match)
if route_path in txt:
    print(f"✅ Route path already exists: {route_path}")
    open(route_file, "w", encoding="utf-8").write(txt)
    raise SystemExit(0)

# Build route block (matches your rent-invoice pattern: org header + transaction + service)
route_block = f"""
// ==========================================================
// PURCHASE PAY (BUY FLOW)
// POST {route_path}
// ==========================================================
{handler_target}.post("{route_path}", async (req, res) => {{
  try {{
    const organizationId =
      (req.headers["x-organization-id"] || req.headers["X-Organization-Id"] || req.headers["x-Organization-id"]);
    const purchaseId = (req.params.purchaseId || req.params.id);

    if (!organizationId) {{
      return res.status(400).json({{ ok: false, error: "x-organization-id header is required" }});
    }}
    if (!purchaseId) {{
      return res.status(400).json({{ ok: false, error: "purchaseId param is required" }});
    }}

    const paymentMethod = (req.body?.paymentMethod || "card");
    const amount = (req.body?.amount ?? null);

    const client = await pool.connect();
    try {{
      await client.query("BEGIN");
      const result = await payPropertyPurchase(client, {{
        organizationId: String(organizationId),
        purchaseId: String(purchaseId),
        paymentMethod,
        amount: amount === null ? null : Number(amount),
      }});
      await client.query("COMMIT");

      return res.json({{
        ok: true,
        alreadyPaid: result.alreadyPaid,
        platformFee: result.platformFee,
        sellerNet: result.sellerNet,
        data: result.purchase,
      }});
    }} catch (e) {{
      try {{ await client.query("ROLLBACK"); }} catch (_) {{}}
      throw e;
    }} finally {{
      client.release();
    }}
  }} catch (err) {{
    const msg = (err && (err.message || err.toString())) || "Unknown error";
    return res.status(400).json({{ ok: false, error: msg }});
  }}
}});
"""

# Insert route block near the rent invoice pay route (best effort):
# If we find "rent-invoices" section, insert after last occurrence.
rent_idx = txt.rfind("rent-invoices")
if rent_idx != -1:
    # insert after the next closing brace of a route block (best effort: just after a nearby newline)
    insert_at = txt.find("\n", rent_idx)
    insert_at = insert_at if insert_at != -1 else len(txt)
    txt = txt[:insert_at] + "\n" + route_block + "\n" + txt[insert_at:]
else:
    # fallback append before export default / module.exports
    m = re.search(r"\nexport\s+default\s+\w+\s*;|\nmodule\.exports\s*=", txt)
    if m:
        txt = txt[:m.start()] + "\n" + route_block + "\n" + txt[m.start():]
    else:
        txt = txt + "\n" + route_block + "\n"

open(route_file, "w", encoding="utf-8").write(txt)
print("✅ PATCHED route file with purchase pay endpoint.")
print(f"   Added: POST {route_path}")
PY

echo "✅ DONE"
echo "➡️ Next:"
echo "  1) restart server: npm run dev"
echo "  2) call the endpoint:"
echo "     curl -sS -X POST \"\$API/v1/purchases/\$PURCHASE_ID/pay\" -H \"content-type: application/json\" -H \"authorization: Bearer \$TOKEN\" -H \"x-organization-id: \$ORG_ID\" -d '{\"paymentMethod\":\"card\",\"amount\":2000}' | jq"
