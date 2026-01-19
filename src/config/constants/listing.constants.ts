export const LISTING_VISIBILITY = ["private", "public"] as const;
export type ListingVisibility = (typeof LISTING_VISIBILITY)[number];

export const LISTING_MODERATION = {
  REQUIRES_APPROVAL: true,
} as const;

export const LISTING_SORTS = ["newest", "price_low", "price_high"] as const;
export type ListingSort = (typeof LISTING_SORTS)[number];
