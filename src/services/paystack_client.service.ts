type PaystackConfig = {
  secretKey: string;
};

type PaystackResponse<T> = {
  status: boolean;
  message?: string;
  data?: T;
};

function requirePaystackSecret(): string {
  const key = String(process.env.PAYSTACK_SECRET_KEY || "").trim();
  if (!key) throw new Error("PAYSTACK_SECRET_KEY is not set");
  return key;
}

async function paystackRequest<T>(cfg: PaystackConfig, path: string, opts: {
  method: "GET" | "POST";
  body?: any;
}): Promise<PaystackResponse<T>> {
  const url = `https://api.paystack.co${path}`;
  const res = await fetch(url, {
    method: opts.method,
    headers: {
      "Authorization": `Bearer ${cfg.secretKey}`,
      "Content-Type": "application/json",
    },
    body: opts.body ? JSON.stringify(opts.body) : undefined,
  });

  const text = await res.text();
  let json: any = null;
  try { json = text ? JSON.parse(text) : null; } catch { json = { status: false, message: text }; }

  if (!res.ok) {
    const msg = json?.message || `Paystack HTTP ${res.status}`;
    throw new Error(msg);
  }

  return json as PaystackResponse<T>;
}

export async function paystackCreateTransferRecipient(args: {
  name: string;
  accountNumber: string;
  bankCode: string;
  currency: string; // NGN
}): Promise<{ recipientCode: string; raw: any }> {
  const cfg = { secretKey: requirePaystackSecret() };

  const body = {
    type: "nuban",
    name: args.name,
    account_number: args.accountNumber,
    bank_code: args.bankCode,
    currency: args.currency,
  };

  const resp = await paystackRequest<{ recipient_code: string }>(cfg, "/transferrecipient", {
    method: "POST",
    body,
  });

  const code = String(resp?.data?.recipient_code || "").trim();
  if (!code) throw new Error("Paystack recipient_code missing");

  return { recipientCode: code, raw: resp };
}

export async function paystackInitiateTransfer(args: {
  amountMajor: number; // e.g. 1500.50
  currency: string;    // NGN
  recipientCode: string;
  reference: string;   // unique
  reason?: string | null;
}): Promise<{ transferCode: string | null; raw: any }> {
  const cfg = { secretKey: requirePaystackSecret() };

  // Paystack expects minor units (kobo) for NGN
  const amountMinor = Math.round(Number(args.amountMajor) * 100);
  if (!Number.isFinite(amountMinor) || amountMinor <= 0) throw new Error("Invalid payout amount");

  const body: any = {
    source: "balance",
    amount: amountMinor,
    recipient: args.recipientCode,
    reference: args.reference,
  };
  if (args.reason) body.reason = args.reason;

  const resp = await paystackRequest<any>(cfg, "/transfer", {
    method: "POST",
    body,
  });

  const transferCode = String(resp?.data?.transfer_code || "").trim() || null;
  return { transferCode, raw: resp };
}
