#!/usr/bin/env bash
set -euo pipefail

FILE="src/services/ledger.service.ts"

if [[ ! -f "$FILE" ]]; then
  echo "❌ Not found: $FILE"
  exit 1
fi

ts="$(date +%Y%m%d_%H%M%S)"
mkdir -p scripts/.bak
cp "$FILE" "scripts/.bak/ledger.service.ts.bak.$ts"
echo "✅ backup -> scripts/.bak/ledger.service.ts.bak.$ts"

node <<'NODE'
const fs = require("fs");

const file = "src/services/ledger.service.ts";
let s = fs.readFileSync(file, "utf8");

function removeDuplicateExportedAsyncFunction(name) {
  // Match blocks like: export async function NAME(...) { ... }
  // We keep the first match and remove all later matches.
  const re = new RegExp(`\\nexport\\s+async\\s+function\\s+${name}\\s*\$begin:math:text$\[\^\\$end:math:text$]*\\)\\s*\\{`, "g");

  const starts = [];
  let m;
  while ((m = re.exec(s)) !== null) starts.push(m.index + 1); // start at newline
  if (starts.length <= 1) return { changed: false, count: starts.length };

  // Find end of each function block via brace counting.
  function findBlockEnd(startIdx) {
    let i = startIdx;
    // move to first "{"
    i = s.indexOf("{", i);
    if (i === -1) return -1;

    let depth = 0;
    let inStr = null;
    let esc = false;

    for (; i < s.length; i++) {
      const ch = s[i];

      if (inStr) {
        if (esc) { esc = false; continue; }
        if (ch === "\\") { esc = true; continue; }
        if (ch === inStr) { inStr = null; continue; }
        continue;
      } else {
        if (ch === "'" || ch === '"' || ch === "`") { inStr = ch; continue; }
        if (ch === "{") depth++;
        if (ch === "}") {
          depth--;
          if (depth === 0) {
            // include trailing newline if present
            let end = i + 1;
            if (s[end] === "\n") end += 1;
            return end;
          }
        }
      }
    }
    return -1;
  }

  // compute blocks (start..end) for each match
  const blocks = starts.map((st) => {
    const end = findBlockEnd(st);
    return { st, end };
  });

  // Remove all but the first. Do it from the end to not shift indices.
  const toRemove = blocks.slice(1).filter(b => b.end > b.st);
  for (let i = toRemove.length - 1; i >= 0; i--) {
    const { st, end } = toRemove[i];
    s = s.slice(0, st) + "\n// (deduped duplicate export removed)\n" + s.slice(end);
  }

  return { changed: true, count: starts.length };
}

const a = removeDuplicateExportedAsyncFunction("debitPlatformFee");
const b = removeDuplicateExportedAsyncFunction("debitPayee");

fs.writeFileSync(file, s, "utf8");

function count(name) {
  const re = new RegExp(`export\\s+async\\s+function\\s+${name}\\b`, "g");
  return (s.match(re) || []).length;
}

console.log(`debitPlatformFee definitions before: ${a.count}`);
console.log(`debitPayee definitions before: ${b.count}`);
NODE

# Verify only one export remains for each
c1="$(grep -c "export async function debitPlatformFee" "$FILE" || true)"
c2="$(grep -c "export async function debitPayee" "$FILE" || true)"

echo "🔎 debitPlatformFee count now: $c1"
echo "�� debitPayee count now: $c2"

if [[ "$c1" -ne 1 || "$c2" -ne 1 ]]; then
  echo "❌ Still duplicates (or missing). Show occurrences:"
  grep -n "export async function debitPlatformFee" -n "$FILE" || true
  grep -n "export async function debitPayee" -n "$FILE" || true
  exit 1
fi

echo "✅ Deduped exports successfully."

# Quick build check (won't start server)
if npm run -s build >/dev/null 2>&1; then
  echo "✅ build OK"
else
  echo "ℹ️ build script not available or failed; running tsc --noEmit"
  npx -y tsc -p tsconfig.json --noEmit
  echo "✅ tsc OK"
fi

echo "NEXT:"
echo "  1) npm run dev"
