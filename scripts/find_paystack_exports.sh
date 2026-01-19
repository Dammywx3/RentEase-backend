#!/usr/bin/env bash
set -euo pipefail

echo "=== Checking common shell files for PAYSTACK exports ==="
files=(
  "$HOME/.zshrc"
  "$HOME/.zprofile"
  "$HOME/.profile"
  "$HOME/.bashrc"
  "$HOME/.bash_profile"
  "$HOME/.config/zsh/.zshrc"
  "$HOME/.config/zsh/.zprofile"
)

found=0
for f in "${files[@]}"; do
  if [[ -f "$f" ]]; then
    if rg -n "PAYSTACK_(SECRET_KEY|WEBHOOK_SECRET|PUBLIC_KEY)" "$f" >/dev/null 2>&1; then
      echo
      echo "--- $f ---"
      rg -n "PAYSTACK_(SECRET_KEY|WEBHOOK_SECRET|PUBLIC_KEY)" "$f" || true
      found=1
    fi
  fi
done

echo
if [[ $found -eq 0 ]]; then
  echo "✅ No PAYSTACK exports found in common shell files."
  echo "If server still uses sk_liv..., it may be coming from:"
  echo " - your terminal app 'environment variables' settings"
  echo " - a process manager (pm2, launchd, etc.)"
  echo " - Render/AWS env vars (for production)"
fi
