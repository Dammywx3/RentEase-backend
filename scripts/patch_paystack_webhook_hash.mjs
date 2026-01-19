import fs from "node:fs";

const file = "src/routes/webhooks.ts";
if (!fs.existsSync(file)) {
  console.error("❌ File not found:", file);
  process.exit(1);
}

let s = fs.readFileSync(file, "utf8");

const startMarker = `      // ---- A) Hash JSON.stringify(body) ----`;
const endMarker = `      if (!ok) {`;

const start = s.indexOf(startMarker);
const end = s.indexOf(endMarker);

if (start === -1 || end === -1 || end <= start) {
  console.error("❌ Patch failed: markers not found.");
  console.error("Found start?", start !== -1, "Found end?", end !== -1);
  console.error("Tip: your file may differ slightly. Run:");
  console.error("  grep -n \"Hash JSON.stringify\" -n src/routes/webhooks.ts");
  console.error("  grep -n \"if (!ok)\" -n src/routes/webhooks.ts");
  process.exit(1);
}

const replacement = `      // ---- A) Hash JSON.stringify(body) ----
      const bodyObj: any = (request as any).body ?? {};
      const bodyString = JSON.stringify(bodyObj);

      // ---- B) Prefer raw body (if available); fallback to JSON string ----
      const rawAny = (request as any).rawBody as Buffer | string | undefined;

      let rawBuf: Buffer | null = null;
      if (Buffer.isBuffer(rawAny)) rawBuf = rawAny;
      else if (typeof rawAny === "string") rawBuf = Buffer.from(rawAny, "utf8");

      // ✅ ALWAYS hash a Buffer (avoids TS union errors)
      const payloadBuf =
        rawBuf && rawBuf.length > 0 ? rawBuf : Buffer.from(bodyString, "utf8");

      const computedHex = crypto
        .createHmac("sha512", secret)
        .update(payloadBuf)
        .digest("hex")
        .toLowerCase();

      let ok = safeTimingEqualHex(signature, computedHex);

`;

s = s.slice(0, start) + replacement + s.slice(end);
fs.writeFileSync(file, s, "utf8");
console.log("✅ Patched:", file);
