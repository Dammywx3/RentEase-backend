export const CONTRACT_STATUSES = ["draft", "sent", "signed", "expired", "cancelled"] as const;
export type ContractStatus = (typeof CONTRACT_STATUSES)[number];

export const SIGNATURE_STATUSES = ["pending", "signed", "declined"] as const;
export type SignatureStatus = (typeof SIGNATURE_STATUSES)[number];
