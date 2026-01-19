export type ListingKind = "owner_direct" | "agent_partner" | "agent_direct";
export type ListingStatus = "draft" | "active" | "paused" | "closed" | "archived";

export type CreateListingBody = {
  propertyId: string;
  kind: ListingKind;

  // only needed for agent_* kinds, enforced in route
  agentId?: string | null;

  // required by DB check constraint chk_listing_payee_present
  payeeUserId: string;

  basePrice: number;
  listedPrice: number;

  // optional
  status?: ListingStatus;
  agentCommissionPercent?: number | null;
  requiresOwnerApproval?: boolean | null;
  isPublic?: boolean | null;
  publicNote?: string | null;
};

export type PatchListingBody = Partial<{
  status: ListingStatus;
  agentId: string | null;
  payeeUserId: string;
  basePrice: number;
  listedPrice: number;
  agentCommissionPercent: number | null;
  requiresOwnerApproval: boolean | null;
  isPublic: boolean | null;
  publicNote: string | null;
}>;
