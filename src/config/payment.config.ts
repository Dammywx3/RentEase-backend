// src/config/payment.config.ts
import { z } from "zod";

const EnvSchema = z.object({
  NODE_ENV: z.string().optional(),

  // Paystack
  PAYSTACK_SECRET_KEY: z.string().min(10, "PAYSTACK_SECRET_KEY is required"),
  PAYSTACK_PUBLIC_KEY: z.string().min(10).optional(),
  PAYSTACK_WEBHOOK_SECRET: z.string().min(10).optional(),
  PAYSTACK_BASE_URL: z.string().url().optional(), // default: https://api.paystack.co
  PAYSTACK_CALLBACK_URL: z.string().url().optional(),
});

type PaymentEnv = z.infer<typeof EnvSchema>;

function readEnv(): PaymentEnv {
  const parsed = EnvSchema.safeParse(process.env);
  if (!parsed.success) {
    const msg = parsed.error.issues
      .map((i) => `${i.path.join(".") || "env"}: ${i.message}`)
      .join("\n");
    throw new Error(`Invalid environment configuration:\n${msg}`);
  }

  const d = parsed.data;

  // ✅ Guard against .env variable "expansion" (dotenv does NOT expand ${VAR})
  // If someone writes PAYSTACK_WEBHOOK_SECRET=${PAYSTACK_SECRET_KEY}
  // your app would literally use the string "${PAYSTACK_SECRET_KEY}" as secret and webhook verification fails.
  if (d.PAYSTACK_WEBHOOK_SECRET && d.PAYSTACK_WEBHOOK_SECRET.includes("${")) {
    throw new Error(
      "PAYSTACK_WEBHOOK_SECRET contains '${...}'. Your .env does not expand variables.\n" +
        "Fix: put the real webhook secret value OR remove PAYSTACK_WEBHOOK_SECRET so it falls back to PAYSTACK_SECRET_KEY."
    );
  }

  // ✅ Also guard secret key just in case
  if (d.PAYSTACK_SECRET_KEY && d.PAYSTACK_SECRET_KEY.includes("${")) {
    throw new Error(
      "PAYSTACK_SECRET_KEY contains '${...}'. Your .env does not expand variables.\n" +
        "Fix: put the real Paystack secret key (sk_test_* or sk_live_*)."
    );
  }

  return d;
}

const env = readEnv();

function isLiveKey(sk: string) {
  return sk.startsWith("sk_live_");
}
function isTestKey(sk: string) {
  return sk.startsWith("sk_test_");
}

export const paymentConfig = {
  provider: "paystack" as const,

  env: (env.NODE_ENV ?? "development") as string,
  isProduction: (env.NODE_ENV ?? "").toLowerCase() === "production",

  paystack: {
    baseUrl: env.PAYSTACK_BASE_URL ?? "https://api.paystack.co",
    secretKey: env.PAYSTACK_SECRET_KEY,
    publicKey: env.PAYSTACK_PUBLIC_KEY ?? null,

    // ✅ Signature verification:
    // Paystack signs webhook payload using your SECRET KEY (HMAC SHA512 on RAW BODY)
    // If you set PAYSTACK_WEBHOOK_SECRET, we use it; otherwise fallback to SECRET KEY.
    webhookSecret: env.PAYSTACK_WEBHOOK_SECRET ?? env.PAYSTACK_SECRET_KEY,

    callbackUrl: env.PAYSTACK_CALLBACK_URL ?? null,

    mode: isLiveKey(env.PAYSTACK_SECRET_KEY)
      ? ("live" as const)
      : isTestKey(env.PAYSTACK_SECRET_KEY)
      ? ("test" as const)
      : ("unknown" as const),
  },
} as const;

if (paymentConfig.paystack.mode === "unknown") {
  // eslint-disable-next-line no-console
  console.warn(
    "[payment.config] PAYSTACK_SECRET_KEY does not look like sk_test_* or sk_live_*. mode=unknown"
  );
}