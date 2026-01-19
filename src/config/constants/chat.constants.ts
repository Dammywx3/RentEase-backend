export const MESSAGE_TYPES = ["text", "image", "file", "system"] as const;
export type MessageType = (typeof MESSAGE_TYPES)[number];

export const CHAT_LIMITS = {
  MAX_MESSAGE_LEN: 4000,
  MAX_ATTACHMENTS: 10,
} as const;
