export const APP = {
  NAME: "RentEase API",
  API_PREFIX: "/v1",
  DEFAULT_PORT: 4000,

  PAGINATION: {
    DEFAULT_LIMIT: 20,
    MAX_LIMIT: 100,
  },

  HEADERS: {
    REQUEST_ID: "x-request-id",
    ORG_ID: "x-organization-id",
  },
} as const;
