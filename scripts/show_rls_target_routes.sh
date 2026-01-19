#!/usr/bin/env bash
set -euo pipefail

ROOT="src/routes"
OUT="rls_target_routes_dump.txt"

FILES=(
  "$ROOT/applications.ts"
  "$ROOT/listings.ts"
  "$ROOT/viewings.ts"
  "$ROOT/me.ts"
  "$ROOT/organizations.ts"
)

echo
echo "============================================================"
echo "RentEase: RLS target route dump"
echo "============================================================"
echo "PWD : $(pwd)"
echo "OUT : $OUT"
echo

: > "$OUT"

for f in "${FILES[@]}"; do
  echo "------------------------------------------------------------"
  echo "FILE: $f"
  echo "------------------------------------------------------------"

  if [[ -f "$f" ]]; then
    # print to terminal
    nl -ba "$f" | sed -n '1,260p'
    if [[ $(wc -l < "$f") -gt 260 ]]; then
      echo
      echo "---- (file continues; showing the rest) ----"
      nl -ba "$f" | sed -n '261,9999p'
    fi

    # also append to OUT file
    {
      echo
      echo "============================================================"
      echo "FILE: $f"
      echo "============================================================"
      nl -ba "$f"
    } >> "$OUT"
  else
    echo "❌ Missing: $f"
    {
      echo
      echo "============================================================"
      echo "FILE: $f"
      echo "============================================================"
      echo "MISSING"
    } >> "$OUT"
  fi

  echo
done

echo "============================================================"
echo "✅ Done. Paste me either:"
echo "  1) the terminal output, OR"
echo "  2) this file:"
echo "     cat $OUT"
echo "============================================================"
