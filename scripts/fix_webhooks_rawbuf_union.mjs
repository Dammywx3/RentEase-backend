import fs from "node:fs";

const file = "src/routes/webhooks.ts";
if (!fs.existsSync(file)) {
  console.error("❌ File not found:", file);
  process.exit(1);
}

let s = fs.readFileSync(file, "utf8");

// The exact buggy snippet (TS red underline): rawBuf ... ? rawBuf : bodyString
const target = "rawBuf && rawBuf.length > 0 ? rawBuf : bodyString";
const replacement = "rawBuf && rawBuf.length > 0 ? rawBuf : Buffer.from(bodyString, \"utf8\")";

if (!s.includes(target)) {
  console.error("❌ Could not find the exact target string to replace.");
  console.error("Searched for:", target);
  console.error("Run this to locate similar code:");
  console.error("  grep -n \"rawBuf\" -n src/routes/webhooks.ts");
  process.exit(1);
}

s = s.replace(target, replacement);

// Ensure Buffer is imported/available (Node has Buffer globally, so ok)
fs.writeFileSync(file, s, "utf8");
console.log("✅ Patched union fix in:", file);
