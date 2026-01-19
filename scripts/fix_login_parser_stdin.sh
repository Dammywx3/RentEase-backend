#!/usr/bin/env bash
set -euo pipefail

FILE="scripts/e2e_close_purchase.sh"
[ -f "$FILE" ] || { echo "❌ Missing $FILE"; exit 1; }

cp -f "$FILE" "$FILE.bak.$(date +%s)"

# Replace the parse_token_org_user() function with a correct version
perl -0777 -i -pe '
s/function\s+parse_token_org_user\(\)\s*\{.*?\n\}/function parse_token_org_user() {\n  local json=\"${1:-}\"\n  local tmp=\"\\/tmp\\/rentease_login_parse_$$.txt\"\n\n  # IMPORTANT: feed JSON to node via stdin\n  printf \"%s\" \"$json\" | node - <<'\''NODE'\'' > \"$tmp\"\nlet raw=\"\";\nprocess.stdin.setEncoding(\"utf8\");\nprocess.stdin.on(\"data\",(c)=>raw+=c);\nprocess.stdin.on(\"end\",()=>{\n  try{\n    const j=JSON.parse(raw||\"{}\");\n    const token=j.token || j.accessToken || j.access_token || (j.data && (j.data.token||j.data.accessToken||j.data.access_token)) || \"\";\n    const org=(j.user && (j.user.organization_id||j.user.organizationId)) || (j.data && j.data.user && (j.data.user.organization_id||j.data.user.organizationId)) || j.org || \"\";\n    const uid=(j.user && (j.user.id||j.user.userId)) || (j.data && j.data.user && (j.data.user.id||j.data.user.userId)) || \"\";\n    console.log(token);\n    console.log(org);\n    console.log(uid);\n  }catch(e){\n    console.log(\"\");\n    console.log(\"\");\n    console.log(\"\");\n  }\n});\nNODE\n\n  TOKEN=\"$(sed -n '\''1p'\'' \"$tmp\" | tr -d \"\\r\")\"\n  ORG_ID=\"$(sed -n '\''2p'\'' \"$tmp\" | tr -d \"\\r\")\"\n  USER_ID=\"$(sed -n '\''3p'\'' \"$tmp\" | tr -d \"\\r\")\"\n  rm -f \"$tmp\"\n}\n/sms' "$FILE"

echo "✅ Patched parser in $FILE"
echo "Quick check (parser lines):"
grep -n "parse_token_org_user" -n "$FILE" | head -n 5
