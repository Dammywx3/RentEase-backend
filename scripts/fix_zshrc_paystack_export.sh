#!/usr/bin/env bash
set -euo pipefail

ZSHRC="$HOME/.zshrc"
if [[ ! -f "$ZSHRC" ]]; then
  echo "❌ Not found: $ZSHRC"
  exit 1
fi

ts="$(date +%s)"
bak="$ZSHRC.bak.$ts"
cp "$ZSHRC" "$bak"
echo "Backup: $bak"

# Comment out ANY PAYSTACK_SECRET_KEY export line(s)
perl -0777 -i -pe '
  s/^\s*export\s+PAYSTACK_SECRET_KEY=.*$/# [DISABLED by fix_zshrc_paystack_export.sh] $&/mg;
' "$ZSHRC"

echo "✅ Patched: $ZSHRC"
echo
echo "---- verify ----"
rg -n "PAYSTACK_SECRET_KEY" "$ZSHRC" || true
echo
echo "Next: restart your terminal OR run: source ~/.zshrc"
