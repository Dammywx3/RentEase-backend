import type { PoolClient } from "pg";
import { withRlsTransaction } from "../config/database.js";
import {
  insertProperty,
  listProperties,
  getPropertyById,
  patchProperty,
} from "../repos/properties.repo.js";

import type { z } from "zod";
import {
  createPropertySchema,
  listPropertiesQuerySchema,
  patchPropertySchema,
} from "../schemas/properties.schema.js";

export type CreatePropertyInput = z.infer<typeof createPropertySchema>;
export type ListPropertiesQuery = z.infer<typeof listPropertiesQuerySchema>;
export type PatchPropertyInput = z.infer<typeof patchPropertySchema>;

export async function createPropertyForOrg(args: {
  userId: string;
  organizationId: string;
  input: CreatePropertyInput;
}) {
  const { userId, organizationId, input } = args;

  return withRlsTransaction({ userId, organizationId }, async (client: PoolClient) => {
    const payload: any = {
      // owner: prefer ownerId if provided; else external owner fields
      owner_id: input.ownerId ?? null,
      owner_external_name: input.ownerExternalName ?? null,
      owner_external_phone: input.ownerExternalPhone ?? null,
      owner_external_email: input.ownerExternalEmail ?? null,

      default_agent_id: input.defaultAgentId ?? null,

      title: input.title,
      description: input.description ?? null,

      type: input.type,
      base_price: input.basePrice,

      // ✅ if undefined => omit so DB default applies
      ...(input.currency !== undefined ? { currency: input.currency } : {}),

      address_line1: input.addressLine1 ?? null,
      address_line2: input.addressLine2 ?? null,
      city: input.city ?? null,
      state: input.state ?? null,
      country: input.country ?? null,
      postal_code: input.postalCode ?? null,

      latitude: input.latitude ?? null,
      longitude: input.longitude ?? null,

      bedrooms: input.bedrooms ?? null,
      bathrooms: input.bathrooms ?? null,
      square_meters: input.squareMeters ?? null,
      year_built: input.yearBuilt ?? null,

      amenities: input.amenities ?? null,

      // ✅ KEY FIX: only include if provided (no more explicit NULL)
      ...(input.status !== undefined ? { status: input.status } : {}),
      ...(input.verificationStatus !== undefined
        ? { verification_status: input.verificationStatus }
        : {}),

      slug: input.slug ?? null,

      created_by: userId,
      updated_by: userId,
    };

    return insertProperty(client, payload);
  });
}

export async function listPropertiesForOrg(args: {
  userId: string;
  organizationId: string;
  query: ListPropertiesQuery;
}) {
  const { userId, organizationId, query } = args;

  return withRlsTransaction({ userId, organizationId }, async (client: PoolClient) => {
    return listProperties(client, {
      limit: query.limit,
      offset: query.offset,
      status: query.status,
      type: query.type,
      city: query.city,
    });
  });
}

export async function getPropertyForOrg(args: {
  userId: string;
  organizationId: string;
  propertyId: string;
}) {
  const { userId, organizationId, propertyId } = args;

  return withRlsTransaction({ userId, organizationId }, async (client: PoolClient) => {
    return getPropertyById(client, propertyId);
  });
}

export async function patchPropertyForOrg(args: {
  userId: string;
  organizationId: string;
  propertyId: string;
  patch: PatchPropertyInput;
}) {
  const { userId, organizationId, propertyId, patch } = args;

  return withRlsTransaction({ userId, organizationId }, async (client: PoolClient) => {
    // map API keys -> DB keys
    const dbPatch: any = {
      ...(patch.ownerId !== undefined ? { owner_id: patch.ownerId } : {}),
      ...(patch.ownerExternalName !== undefined
        ? { owner_external_name: patch.ownerExternalName }
        : {}),
      ...(patch.ownerExternalPhone !== undefined
        ? { owner_external_phone: patch.ownerExternalPhone }
        : {}),
      ...(patch.ownerExternalEmail !== undefined
        ? { owner_external_email: patch.ownerExternalEmail }
        : {}),
      ...(patch.defaultAgentId !== undefined ? { default_agent_id: patch.defaultAgentId } : {}),

      ...(patch.title !== undefined ? { title: patch.title } : {}),
      ...(patch.description !== undefined ? { description: patch.description } : {}),
      ...(patch.type !== undefined ? { type: patch.type } : {}),
      ...(patch.basePrice !== undefined ? { base_price: patch.basePrice } : {}),
      ...(patch.currency !== undefined ? { currency: patch.currency } : {}),

      ...(patch.addressLine1 !== undefined ? { address_line1: patch.addressLine1 } : {}),
      ...(patch.addressLine2 !== undefined ? { address_line2: patch.addressLine2 } : {}),
      ...(patch.city !== undefined ? { city: patch.city } : {}),
      ...(patch.state !== undefined ? { state: patch.state } : {}),
      ...(patch.country !== undefined ? { country: patch.country } : {}),
      ...(patch.postalCode !== undefined ? { postal_code: patch.postalCode } : {}),

      ...(patch.latitude !== undefined ? { latitude: patch.latitude } : {}),
      ...(patch.longitude !== undefined ? { longitude: patch.longitude } : {}),

      ...(patch.bedrooms !== undefined ? { bedrooms: patch.bedrooms } : {}),
      ...(patch.bathrooms !== undefined ? { bathrooms: patch.bathrooms } : {}),
      ...(patch.squareMeters !== undefined ? { square_meters: patch.squareMeters } : {}),
      ...(patch.yearBuilt !== undefined ? { year_built: patch.yearBuilt } : {}),

      ...(patch.amenities !== undefined ? { amenities: patch.amenities } : {}),
      ...(patch.status !== undefined ? { status: patch.status } : {}),
      ...(patch.verificationStatus !== undefined
        ? { verification_status: patch.verificationStatus }
        : {}),
      ...(patch.slug !== undefined ? { slug: patch.slug } : {}),

      updated_by: userId,
    };

    return patchProperty(client, propertyId, dbPatch);
  });
}
