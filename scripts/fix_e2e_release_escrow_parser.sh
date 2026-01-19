#!/usr/bin/env bash
set -euo pipefail

FILE="scripts/e2e_release_escrow.sh"
if [ ! -f "$FILE" ]; then
  echo "Missing $FILE. Create it first."
  exit 1
fi

perl -0777 -i -pe 's/read -r TOKEN ORG_ID USER_ID <<EOF.*?EOF/OUT_FILE="\\/tmp\\/rentease_login_parse_$$.txt"\nprintf "%s" "$LOGIN_JSON" | node - <<'\''NODE'\'' > "$OUT_FILE"\nlet raw = \"\";\nprocess.stdin.setEncoding(\"utf8\");\nprocess.stdin.on(\"data\", (c)=> raw += c);\nprocess.stdin.on(\"end\", ()=>{\n  try {\n    const j = JSON.parse(raw || \"{}\");\n    if (j && j.ok === false) {\n      console.error(\"LOGIN_FAILED:\", j.error || \"UNKNOWN\", \"-\", (j.message || \"\"));\n      process.exit(10);\n    }\n    const token = j.token || j.accessToken || j.access_token || (j.data && (j.data.token || j.data.accessToken || j.data.access_token)) || \"\";\n    const orgId = (j.user && (j.user.organization_id || j.user.organizationId)) || (j.data && j.data.user && (j.data.user.organization_id || j.data.user.organizationId)) || j.org || \"\";\n    const userId = (j.user && (j.user.id || j.user.userId)) || (j.data && j.data.user && (j.data.user.id || j.data.user.userId)) || \"\";\n    if (!token) { console.error(\"LOGIN_FAILED: token not found\"); process.exit(11); }\n    if (!orgId) { console.error(\"LOGIN_FAILED: organization_id not found\"); process.exit(12); }\n    process.stdout.write(token + \"\\n\" + orgId + \"\\n\" + userId + \"\\n\");\n  } catch (e) {\n    console.error(\"LOGIN_FAILED: invalid JSON\");\n    process.exit(13);\n  }\n});\nNODE\nTOKEN="$(sed -n '\''1p'\'' "$OUT_FILE" | tr -d '\''\\r'\'')"\nORG_ID="$(sed -n '\''2p'\'' "$OUT_FILE" | tr -d '\''\\r'\'')"\nUSER_ID="$(sed -n '\''3p'\'' "$OUT_FILE" | tr -d '\''\\r'\'')"\nrm -f "$OUT_FILE"\n\nif [ -z "$TOKEN" ] || [ -z "$ORG_ID" ]; then\n  echo \"LOGIN_PARSE_FAILED: TOKEN or ORG_ID empty\" >&2\n  exit 20\nfi/sms' "$FILE"

echo "✅ Patched $FILE (token/org parser now reliable)"
echo "➡️  Now run:"
echo "   export DEV_EMAIL='dev_1768638237@rentease.local'"
echo "   export DEV_PASS='Passw0rd!234'"
echo "   ./scripts/e2e_release_escrow.sh 5ae53ce5-433d-4966-a1e8-edb8d0f6d1ae"
