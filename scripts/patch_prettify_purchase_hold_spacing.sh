#!/usr/bin/env bash
set -euo pipefail

FILE="${FILE_PATH:-src/routes/purchases.routes.ts}"

python3 - <<'PY'
import os, re
path = os.environ.get("FILE_PATH", "src/routes/purchases.routes.ts")
txt = open(path, "r", encoding="utf-8").read()

# Add newline after assertRlsContextWithUser(client);
txt2 = re.sub(
    r"(await assertRlsContextWithUser\(client\);\s*)const purchase =",
    r"\\1\n        const purchase =",
    txt
)

if txt2 == txt:
    print("[ABORT] No changes applied (already formatted or pattern not found).")
else:
    open(path, "w", encoding="utf-8").write(txt2)
    print("✅ Prettified spacing in hold route.")
PY
