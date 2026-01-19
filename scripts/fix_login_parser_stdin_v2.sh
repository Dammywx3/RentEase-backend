#!/usr/bin/env bash
set -euo pipefail

FILE="scripts/e2e_close_purchase.sh"
[ -f "$FILE" ] || { echo "❌ Missing $FILE"; exit 1; }

cp -f "$FILE" "$FILE.bak.$(date +%s)"

TMP="$(mktemp)"

# 1) Replace parse_token_org_user() implementation safely (no perl)
awk '
function countchar(s, c,   t) { t=s; return gsub(c,"",t) }

BEGIN { skipping=0; depth=0 }

{
  if (skipping==0 && $0 ~ /^[[:space:]]*(function[[:space:]]+)?parse_token_org_user[[:space:]]*\(\)[[:space:]]*\{[[:space:]]*$/) {
    print "parse_token_org_user() {"
    print "  # Reads login JSON from STDIN and sets TOKEN/ORG_ID/USER_ID"
    print "  local tmp=\"/tmp/rentease_login_parse_$$.txt\""
    print "  node - <<'\''NODE'\'' > \"$tmp\""
    print "let raw=\"\";"
    print "process.stdin.setEncoding(\"utf8\");"
    print "process.stdin.on(\"data\", c => raw += c);"
    print "process.stdin.on(\"end\", () => {"
    print "  try {"
    print "    const j = JSON.parse(raw || \"{}\");"
    print "    const token = j.token || j.accessToken || j.access_token || (j.data && (j.data.token || j.data.accessToken || j.data.access_token)) || \"\";"
    print "    const orgId = (j.user && (j.user.organization_id || j.user.organizationId)) || (j.data && j.data.user && (j.data.user.organization_id || j.data.user.organizationId)) || j.org || \"\";"
    print "    const userId = (j.user && (j.user.id || j.user.userId)) || (j.data && j.data.user && (j.data.user.id || j.data.user.userId)) || \"\";"
    print "    process.stdout.write(token + \"\\n\" + orgId + \"\\n\" + userId + \"\\n\");"
    print "  } catch (e) {"
    print "    process.stdout.write(\"\\n\\n\\n\");"
    print "  }"
    print "});"
    print "NODE"
    print ""
    print "  TOKEN=\"$(sed -n '\''1p'\'' \"$tmp\" | tr -d \"\\r\")\""
    print "  ORG_ID=\"$(sed -n '\''2p'\'' \"$tmp\" | tr -d \"\\r\")\""
    print "  USER_ID=\"$(sed -n '\''3p'\'' \"$tmp\" | tr -d \"\\r\")\""
    print "  rm -f \"$tmp\""
    print "}"
    skipping=1

    # start brace depth based on current line (function header has 1 open)
    opens = countchar($0, "{")
    closes = countchar($0, "}")
    depth = opens - closes
    next
  }

  if (skipping==1) {
    opens = countchar($0, "{")
    closes = countchar($0, "}")
    depth += (opens - closes)

    # once depth <= 0, we have passed the end of old function
    if (depth <= 0) {
      skipping=0
    }
    next
  }

  print
}
' "$FILE" > "$TMP"

mv "$TMP" "$FILE"
chmod +x "$FILE"

# 2) Update call sites to pipe JSON into parser
# (macOS sed -i needs a backup suffix)
sed -i.bak2 \
  -e 's/^[[:space:]]*parse_token_org_user[[:space:]]*"\$LOGIN_BODY"[[:space:]]*$/printf "%s" "$LOGIN_BODY" | parse_token_org_user/' \
  -e 's/^[[:space:]]*parse_token_org_user[[:space:]]*"\$LOGIN_JSON"[[:space:]]*$/printf "%s" "$LOGIN_JSON" | parse_token_org_user/' \
  -e 's/^[[:space:]]*parse_token_org_user[[:space:]]*"\$LOGIN_RESPONSE"[[:space:]]*$/printf "%s" "$LOGIN_RESPONSE" | parse_token_org_user/' \
  "$FILE" || true

echo "✅ Patched parser + call site in $FILE"
echo
echo "==> Sanity check:"
grep -n "parse_token_org_user" -n "$FILE" | head -n 20
echo
echo "Run:"
echo "  export DEV_EMAIL='dev_1768638237@rentease.local'"
echo "  export DEV_PASS='Passw0rd!234'"
echo "  ./scripts/e2e_close_purchase.sh 5ae53ce5-433d-4966-a1e8-edb8d0f6d1ae"
