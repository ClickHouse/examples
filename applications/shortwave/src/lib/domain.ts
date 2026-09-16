import { z } from "zod";
import type { QrStyle, UtmValues } from "./types";
import { CLICKHOUSE_QR_LOGO } from "./qr-logo";

export const utmKeys = [
  "source",
  "medium",
  "campaign",
  "term",
  "content",
] as const;
export const utmSchema = z
  .object({
    source: z.string().trim().max(200).optional(),
    medium: z.string().trim().max(200).optional(),
    campaign: z.string().trim().max(200).optional(),
    term: z.string().trim().max(200).optional(),
    content: z.string().trim().max(200).optional(),
  })
  .strict();

export function validateDestination(value: string): string {
  if (value.length > 4096 || /[\u0000-\u001f\u007f]/.test(value))
    throw new Error("Enter a valid URL under 4,096 characters.");
  const input = value.trim();
  const explicitWebScheme = /^https?:\/\//i.test(input);
  const hostWithPort = /^(?:localhost|(?:[^\s:/?#@]+\.)+[^\s:/?#@]+):\d+(?:[/?#]|$)/i.test(input);
  if (!input || input.includes("\\") || (!explicitWebScheme && /^[a-z][a-z0-9+.-]*:/i.test(input) && !hostWithPort)) {
    throw new Error("Enter a web address, using HTTP or HTTPS without embedded credentials.");
  }
  // Protocol-relative addresses also default to HTTPS. A single slash is a path.
  const address = input.startsWith("//") ? input.slice(2) : input;
  if (!explicitWebScheme && /^[/?#]/.test(address))
    throw new Error("Enter a web address such as example.com/path.");
  let url: URL;
  try {
    url = new URL(explicitWebScheme ? input : `https://${address}`);
  } catch {
    throw new Error("Enter a web address such as example.com/path.");
  }
  if (
    !["https:", "http:"].includes(url.protocol) ||
    !url.hostname ||
    url.username ||
    url.password
  ) {
    throw new Error("Use an HTTP or HTTPS URL without embedded credentials.");
  }
  // Avoid interpreting a relative path (for example, docs/setup) as a host.
  const hostname = url.hostname.replace(/\.$/, "");
  if (!explicitWebScheme && hostname !== "localhost" && !hostname.startsWith("[") &&
    (!hostname.includes(".") || hostname.split(".").some((label) => !label))) {
    throw new Error("Enter a web address such as example.com/path.");
  }
  if (url.toString().length > 4096)
    throw new Error("Enter a valid URL under 4,096 characters.");
  return url.toString();
}

export function validateSlug(value: string): string {
  const slug = value.trim();
  if (!/^[a-zA-Z0-9][a-zA-Z0-9_-]{2,47}$/.test(slug))
    throw new Error(
      "Use 3–48 letters, numbers, hyphens, or underscores for the slug.",
    );
  return slug;
}

/** Explicit nonempty values replace existing UTMs; empty values remove them; omitted values survive. */
export function mergeUtm(
  destination: string,
  input: UtmValues = {},
): { resolvedUrl: string; utm: UtmValues } {
  const url = new URL(validateDestination(destination));
  const values = utmSchema.parse(input);
  const snapshot: UtmValues = {};
  for (const key of utmKeys) {
    const param = `utm_${key}`;
    if (values[key] !== undefined) {
      if (values[key]) url.searchParams.set(param, values[key]!);
      else url.searchParams.delete(param);
    }
    const value = url.searchParams.get(param);
    // Inherited values must remain editable under the form's UTM limit.
    if (value) snapshot[key] = z.string().max(200).parse(value);
  }
  if (url.toString().length > 8192)
    throw new Error("The resulting destination URL is too long.");
  return { resolvedUrl: url.toString(), utm: snapshot };
}

export const linkInputSchema = z
  .object({
    destination: z.string().transform(validateDestination),
    title: z.string().trim().max(160).default(""),
    slug: z.string().transform(validateSlug).optional(),
    domainId: z.string().uuid().nullable().optional(),
    utm: utmSchema.default({}),
    tags: z
      .array(z.string().trim().min(1).max(40))
      .max(12)
      .default([])
      .transform((tags) => [...new Set(tags)]),
    folderId: z.string().uuid().nullable().optional(),
    enabled: z.boolean().default(true),
  })
  .strict();

export const defaultQrStyle: QrStyle = {
  foreground: "#171717",
  background: "#ffffff",
  dots: "square",
  logo: CLICKHOUSE_QR_LOGO,
};
export const qrStyleSchema = z
  .object({
    foreground: z.string().regex(/^#[0-9a-fA-F]{6}$/),
    background: z.string().regex(/^#[0-9a-fA-F]{6}$/),
    dots: z.enum(["square", "rounded", "dots"]),
    logo: z.union([z.literal(CLICKHOUSE_QR_LOGO), z
      .string()
      .max(180_000)
      .regex(/^data:image\/(png|jpeg|webp);base64,[A-Za-z0-9+/]+=*$/)])
      .nullish().transform((logo) => logo ?? CLICKHOUSE_QR_LOGO),
  })
  .strict()
  .refine((style) => contrastRatio(style.foreground, style.background) >= 4.5, {
    message:
      "Choose colours with at least 4.5:1 contrast so the QR code stays readable.",
  });

export function contrastRatio(first: string, second: string): number {
  const luminance = (hex: string) => {
    const channels = [1, 3, 5]
      .map((offset) => parseInt(hex.slice(offset, offset + 2), 16) / 255)
      .map((value) =>
        value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4,
      );
    return (
      channels[0]! * 0.2126 + channels[1]! * 0.7152 + channels[2]! * 0.0722
    );
  };
  const a = luminance(first),
    b = luminance(second);
  return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
}

export function requestDimensions(referrer?: string | null, userAgent = "") {
  let referrerDomain = "";
  try {
    if (referrer)
      referrerDomain = new URL(referrer).hostname.toLowerCase().slice(0, 253);
  } catch {
    /* Direct or malformed referrer. */
  }
  const isBot = /bot|crawler|spider|preview|slurp|facebookexternalhit/i.test(
    userAgent,
  );
  const device = /ipad|tablet/i.test(userAgent)
    ? "Tablet"
    : /mobile|iphone|android/i.test(userAgent)
      ? "Mobile"
      : userAgent
        ? "Desktop"
        : "Unknown";
  const browser = /edg\//i.test(userAgent)
    ? "Edge"
    : /firefox\//i.test(userAgent)
      ? "Firefox"
      : /chrome\//i.test(userAgent)
        ? "Chrome"
        : /safari\//i.test(userAgent)
          ? "Safari"
          : "Unknown";
  return {
    referrer_domain: referrerDomain,
    device,
    browser,
    is_bot: Number(isBot),
    country: "Unknown",
  };
}
