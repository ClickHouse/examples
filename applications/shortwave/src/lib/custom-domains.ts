export const DOMAIN_VERIFICATION_LABEL = "_shortwave-verification";
export const DOMAIN_VERIFICATION_PREFIX = "shortwave-verification=";
export const MAX_CUSTOM_DOMAIN_LENGTH = 253 - DOMAIN_VERIFICATION_LABEL.length - 1;
export const DOMAIN_CHECK_INTERVAL_MS = 10_000;
export const MAX_CUSTOM_DOMAINS = 20;

export type CustomDomain = {
  id: string;
  hostname: string;
  status: "pending" | "verified";
  routingReady: boolean;
  verificationName: string;
  verificationValue: string;
  verifiedAt: string | null;
  lastCheckedAt: string | null;
  verificationError: string | null;
  createdAt: string;
};
