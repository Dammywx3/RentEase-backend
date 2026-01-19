#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

FILE="src/routes/purchases.routes.ts"
if [ ! -f "$FILE" ]; then
  echo "❌ File not found: $FILE"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP="$FILE.bak.$TS"
cp "$FILE" "$BACKUP"
echo "==> Backup: $BACKUP"

# ------------------------------------------------------------
# 1) DEDUPE: If the file got pasted twice, it usually repeats from:
#    // src/routes/purchases.routes.ts
#    Keep only up to the FIRST copy.
# ------------------------------------------------------------
TMP="$(mktemp)"
awk '
  BEGIN { c=0 }
  /^\/\/ src\/routes\/purchases\.routes\.ts/ {
    c++
    if (c > 1) exit
  }
  { print }
' "$FILE" > "$TMP"
mv "$TMP" "$FILE"
echo "✅ Dedupe applied (if duplicate existed)."

# ------------------------------------------------------------
# 2) Normalize /status route schema properties block
# ------------------------------------------------------------
perl -0777 -i -pe '
  s@(
    "/purchases/:purchaseId/status",\s*
    \{\s*
      preHandler:\s*requireAuth,\s*
      schema:\s*\{\s*
        body:\s*\{\s*
          type:\s*"object",\s*
          required:\s*\[\s*"status"\s*\],\s*
          additionalProperties:\s*false,\s*
          properties:\s*\{
  )
  [\s\S]*?
  (\}\s*,\s*\}\s*,\s*\}\s*,\s*\},\s*async\s*\()@${1}
          status: {
            type: "string",
            minLength: 1,
            enum: [
              "initiated",
              "offer_made",
              "offer_accepted",
              "under_contract",
              "paid",
              "escrow_opened",
              "deposit_paid",
              "inspection",
              "financing",
              "appraisal",
              "title_search",
              "closing_scheduled",
              "closed",
              "cancelled",
              "refunded"
            ],
          },
          note: { type: "string", minLength: 1 },
        },$2@gsx
' "$FILE"

echo "✅ /status schema normalized."

echo
echo "==> Quick verify (show status route area):"
nl -ba "$FILE" | sed -n '250,360p'
