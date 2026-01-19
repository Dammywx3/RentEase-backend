export const PAYMENT_STATUSES = ["pending", "succeeded", "failed", "refunded", "cancelled"] as const;
export type PaymentStatus = (typeof PAYMENT_STATUSES)[number];

export const PAYMENT_PROVIDERS = ["stripe", "paystack", "flutterwave", "manual"] as const;
export type PaymentProvider = (typeof PAYMENT_PROVIDERS)[number];
