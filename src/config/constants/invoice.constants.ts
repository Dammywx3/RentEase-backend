export const INVOICE_STATUSES = ["draft", "issued", "paid", "overdue", "void"] as const;
export type InvoiceStatus = (typeof INVOICE_STATUSES)[number];
