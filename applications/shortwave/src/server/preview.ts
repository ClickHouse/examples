import { lookup } from "node:dns/promises";
import { request as httpRequest } from "node:http";
import { request as httpsRequest } from "node:https";
import { isIP } from "node:net";
import type { DestinationMetadata } from "../lib/preview";
import { isWorkersRuntime } from "./runtime";

const HTML_LIMIT = 1024 * 1024;
const IMAGE_LIMIT = 512 * 1024;
const unavailable: DestinationMetadata = { status: "unavailable", title: "", description: "", siteName: "", image: null, imageAlt: "" };

// Conservative public-address allowlist: mapped/translated IPv4, local,
// multicast, documentation and special-purpose ranges are never fetched.
export function isPublicAddress(address: string): boolean {
  const family = isIP(address);
  if (family === 4) {
    const [a, b, c] = address.split(".").map(Number);
    return !(a === 0 || a === 10 || a === 127 || a >= 224 ||
      (a === 100 && b >= 64 && b <= 127) || (a === 169 && b === 254) ||
      (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) ||
      (a === 192 && b === 0 && (c === 0 || c === 2)) ||
      (a === 192 && b === 88 && c === 99) ||
      (a === 198 && (b === 18 || b === 19 || (b === 51 && c === 100))) ||
      (a === 203 && b === 0 && c === 113));
  }
  if (family !== 6 || address.includes("%")) return false;
  const [first, second = "0"] = address.toLowerCase().split(":");
  const prefix = parseInt(first, 16);
  return prefix >= 0x2000 && prefix <= 0x3fff && prefix !== 0x2002 &&
    prefix !== 0x3fff && !(prefix === 0x2001 &&
      (parseInt(second || "0", 16) < 0x200 || parseInt(second, 16) === 0xdb8));
}

export function previewTarget(value: string): URL {
  if (typeof value !== "string" || value.length > 4096 || /[\u0000-\u0020\u007f]/.test(value)) throw new Error("Invalid preview URL");
  const url = new URL(value);
  if (!["http:", "https:"].includes(url.protocol) || url.username || url.password || url.port) throw new Error("Unsupported preview URL");
  const host = url.hostname.replace(/^\[|\]$/g, "");
  if (!host || (isIP(host) && !isPublicAddress(host))) throw new Error("Private preview URL");
  url.hash = "";
  return url;
}

type ResolvedAddress = { address: string; family: number };
export async function resolvePreviewAddress(url: URL, resolve: (host: string) => Promise<ResolvedAddress[]> = (host) => lookup(host, { all: true })): Promise<ResolvedAddress> {
  const host = url.hostname.replace(/^\[|\]$/g, "");
  const addresses = isIP(host) ? [{ address: host, family: isIP(host) }] : await resolve(host);
  if (!addresses.length || addresses.some(({ address }) => !isPublicAddress(address))) throw new Error("Private preview address");
  return addresses[0];
}

export async function beforeDeadline<T>(promise: Promise<T>, deadline: number): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([promise, new Promise<never>((_, reject) => {
      timer = setTimeout(() => reject(new Error("Preview timed out")), Math.max(1, deadline - Date.now()));
    })]);
  } finally { clearTimeout(timer); }
}

type Page = { body: Buffer; url: URL; type: string };
export async function readPublicResource(
  value: string,
  kind: "html" | "image",
  deadline: number,
  dependencies: { resolve?: (host: string) => Promise<ResolvedAddress[]>; request?: typeof httpRequest } = {},
): Promise<Page> {
  if (isWorkersRuntime() && !dependencies.request) {
    const { readWorkersPublicResource } = await import("./preview-workers");
    return readWorkersPublicResource(value, kind, deadline, dependencies);
  }
  let url = previewTarget(value);
  for (let redirect = 0; redirect <= 3; redirect++) {
    if (Date.now() >= deadline) throw new Error("Preview timed out");
    const address = await beforeDeadline(resolvePreviewAddress(url, dependencies.resolve), deadline);
    const result: Page | { location: string } = await new Promise((resolve, reject) => {
      const limit = kind === "html" ? HTML_LIMIT : IMAGE_LIMIT;
      const request = dependencies.request || (url.protocol === "https:" ? httpsRequest : httpRequest);
      const req = request(url, {
        method: "GET", agent: false,
        // The checked address is pinned to this connection. Keep the original
        // hostname for Host/SNI and normal TLS certificate verification.
        family: address.family,
        lookup: (_hostname, _options, callback) => callback(null, address.address, address.family),
        headers: { "user-agent": "Shortwave-Preview/1.0", accept: kind === "html" ? "text/html,application/xhtml+xml" : "image/png,image/jpeg,image/gif,image/webp", "accept-encoding": "identity" },
      }, (response) => {
        const status = response.statusCode || 0;
        if ([301, 302, 303, 307, 308].includes(status) && response.headers.location) {
          resolve({ location: response.headers.location });
          response.destroy();
          return;
        }
        const type = (response.headers["content-type"] || "").split(";")[0].trim().toLowerCase();
        const validType = kind === "html" ? ["text/html", "application/xhtml+xml"].includes(type) : ["image/png", "image/jpeg", "image/gif", "image/webp"].includes(type);
        if (status < 200 || status >= 300 || !validType || (response.headers["content-encoding"] && response.headers["content-encoding"] !== "identity") || Number(response.headers["content-length"] || 0) > limit) {
          reject(new Error("Unsupported preview response"));
          response.destroy();
          return;
        }
        const chunks: Buffer[] = [];
        let size = 0;
        response.on("data", (chunk: Buffer) => {
          size += chunk.length;
          if (size > limit) { reject(new Error("Preview response too large")); response.destroy(); }
          else chunks.push(chunk);
        });
        response.on("end", () => resolve({ body: Buffer.concat(chunks), type, url }));
        response.on("error", reject);
        response.on("aborted", () => reject(new Error("Preview response interrupted")));
      });
      const timer = setTimeout(() => req.destroy(new Error("Preview timed out")), Math.max(1, deadline - Date.now()));
      req.on("close", () => clearTimeout(timer));
      req.on("error", reject);
      req.end();
    });
    if ("body" in result) return result;
    // Resolve and validate *every* redirect, including protocol-relative URLs.
    url = previewTarget(new URL(result.location, url).href);
  }
  throw new Error("Too many preview redirects");
}

function decode(value: string): string {
  return value.replace(/&(#x[0-9a-f]+|#\d+|amp|quot|apos|lt|gt|nbsp);/gi, (entity, key: string) => {
    if (key[0] !== "#") return ({ amp: "&", quot: '"', apos: "'", lt: "<", gt: ">", nbsp: " " } as Record<string, string>)[key.toLowerCase()] || entity;
    const point = key[1].toLowerCase() === "x" ? parseInt(key.slice(2), 16) : Number(key.slice(1));
    return point > 0 && point <= 0x10ffff && !(point >= 0xd800 && point <= 0xdfff) ? String.fromCodePoint(point) : "";
  }).replace(/[\u0000-\u001f\u007f]/g, " ").trim();
}

export function parsePreviewMetadata(html: string, base: URL) {
  const head = html.split(/<\/head\s*>/i)[0].replace(/<!--[\s\S]*?-->|<script\b[^>]*>[\s\S]*?<\/script\s*>|<style\b[^>]*>[\s\S]*?<\/style\s*>/gi, "");
  const values = new Map<string, string>();
  for (const match of head.matchAll(/<meta\b(?:[^>"']|"[^"]*"|'[^']*')*>/gi)) {
    const attributes = new Map<string, string>();
    for (const attribute of match[0].matchAll(/([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/g)) attributes.set(attribute[1].toLowerCase(), decode(attribute[2] ?? attribute[3] ?? attribute[4]));
    const key = (attributes.get("property") || attributes.get("name") || "").toLowerCase();
    if (!values.has(key) && attributes.has("content")) values.set(key, attributes.get("content")!);
  }
  const title = (values.get("og:title") || values.get("twitter:title") || decode(head.match(/<title\b[^>]*>([\s\S]*?)<\/title\s*>/i)?.[1] || "")).slice(0, 300);
  const description = (values.get("og:description") || values.get("twitter:description") || values.get("description") || "").slice(0, 600);
  let imageUrl: string | null = null;
  const candidate = values.get("og:image:secure_url") || values.get("og:image") || values.get("twitter:image");
  if (candidate) { try { imageUrl = previewTarget(new URL(candidate, base).href).href; } catch { /* Text preview remains useful. */ } }
  return { title, description, imageUrl, siteName: (values.get("og:site_name") || base.hostname).slice(0, 120), imageAlt: (values.get("og:image:alt") || "").slice(0, 300) };
}

export function imageData(body: Buffer, type: string): string | null {
  if (body.length > IMAGE_LIMIT) return null;
  const valid = (type === "image/png" && body.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) ||
    (type === "image/jpeg" && body[0] === 0xff && body[1] === 0xd8 && body[2] === 0xff) ||
    (type === "image/gif" && ["GIF87a", "GIF89a"].includes(body.subarray(0, 6).toString())) ||
    (type === "image/webp" && body.subarray(0, 4).toString() === "RIFF" && body.subarray(8, 12).toString() === "WEBP");
  return valid ? `data:${type};base64,${body.toString("base64")}` : null;
}

const cache = new Map<string, { expires: number; value: DestinationMetadata }>();
const pending = new Map<string, Promise<DestinationMetadata>>();
const usersPending = new Map<string, number>();
let activePreviews = 0;
export async function destinationPreview(userId: string, destination: string): Promise<DestinationMetadata> {
  if (!userId) throw new Error("Please sign in to continue.");
  let url: URL;
  try { url = previewTarget(destination); } catch { return unavailable; }
  const key = JSON.stringify([userId, url.href]);
  const cached = cache.get(key);
  if (cached && cached.expires > Date.now()) return cached.value;
  // workerd forbids awaiting another request's in-flight I/O. Completed data
  // can be cached, but pending promises are shared only by the Node server.
  const sharePending = !isWorkersRuntime();
  const existing = sharePending ? pending.get(key) : undefined;
  if (existing) return existing;
  if (activePreviews >= 6 || (usersPending.get(userId) || 0) >= 2) return unavailable;
  const task = (async () => {
    let value = unavailable;
    try {
      const deadline = Date.now() + 10_000;
      const page = await readPublicResource(url.href, "html", deadline);
      const { imageUrl, ...metadata } = parsePreviewMetadata(page.body.toString("utf8"), page.url);
      let image: string | null = null;
      if (imageUrl) {
        try { const result = await readPublicResource(imageUrl, "image", deadline); image = imageData(result.body, result.type); } catch { /* Preserve metadata if its image fails. */ }
      }
      value = { ...metadata, image, status: "ready" };
    } catch { /* Never return network/internal details or fetched markup. */ }
    if (cache.size >= 32) cache.delete(cache.keys().next().value!);
    cache.set(key, { value, expires: Date.now() + (value.status === "ready" ? 10 * 60_000 : 30_000) });
    return value;
  })();
  if (sharePending) pending.set(key, task);
  activePreviews++;
  usersPending.set(userId, (usersPending.get(userId) || 0) + 1);
  try { return await task; } finally {
    if (sharePending) pending.delete(key);
    activePreviews--;
    const remaining = (usersPending.get(userId) || 1) - 1;
    if (remaining) usersPending.set(userId, remaining); else usersPending.delete(userId);
  }
}
