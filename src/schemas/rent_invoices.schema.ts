import { z } from "zod";

export const InvoiceStatusSchema = z.enum([
  "draft",
  "issued",
  "paid",
  "overdue",
  "void",
  "cancelled",
]);
export type InvoiceStatus = z.infer<typeof InvoiceStatusSchema>;

export const PaymentMethodSchema = z.enum(["card", "bank_transfer", "wallet"]);
export type PaymentMethod = z.infer<typeof PaymentMethodSchema>;

export const RentInvoiceRowSchema = z.object({
  id: z.string().uuid(),
  organization_id: z.string().uuid(),
  tenancy_id: z.string().uuid(),
  tenant_id: z.string().uuid(),
  property_id: z.string().uuid(),

  invoice_number: z.coerce.number().int().nullable().optional(),
  status: InvoiceStatusSchema,

  period_start: z.string(), // YYYY-MM-DD
  period_end: z.string(), // YYYY-MM-DD
  due_date: z.string(), // YYYY-MM-DD

  subtotal: z.string(),
  late_fee_amount: z.string().nullable().optional(),
  total_amount: z.string(),

  currency: z.string().length(3).nullable().optional(),
  paid_amount: z.string().nullable().optional(),
  paid_at: z.string().nullable().optional(),

  notes: z.string().nullable().optional(),

  created_at: z.string(),
  updated_at: z.string(),
  deleted_at: z.string().nullable(),
});

export const ListRentInvoicesQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(200).default(20),
  offset: z.coerce.number().int().min(0).default(0),
  tenancyId: z.string().uuid().optional(),
  tenantId: z.string().uuid().optional(),
  propertyId: z.string().uuid().optional(),
  status: InvoiceStatusSchema.optional(),
});

export const GenerateRentInvoiceBodySchema = z.object({
  periodStart: z.string(), // YYYY-MM-DD
  periodEnd: z.string(), // YYYY-MM-DD
  dueDate: z.string(), // YYYY-MM-DD

  subtotal: z.number().positive().optional(),
  lateFeeAmount: z.number().nonnegative().nullable().optional(),
  currency: z.string().length(3).nullable().optional(),
  status: InvoiceStatusSchema.nullable().optional(),
  notes: z.string().nullable().optional(),
});

export const PayRentInvoiceBodySchema = z.object({
  paymentMethod: PaymentMethodSchema,
  // Accepts "2000" or 2000. Optional. Can also be null.
  amount: z.coerce.number().positive().nullable().optional(),
});