import { resolve4, resolve6 } from "node:dns/promises";
import { beforeDeadline, previewTarget, resolvePreviewAddress } from "./preview";
import { isWorkersRuntime } from "./runtime";

type Address = { address: string; family: number };
type Kind = "html" | "image";
type PreviewFetch = (url: string, init: RequestInit) => Promise<Response>;

// Workers implements resolve4/6 through DNS over HTTPS, but not dns.lookup.
export async function resolveWorkersPreviewAddresses(host: string): Promise<Address[]> {
  const answers = await Promise.all([resolve4(host), resolve6(host)].map(async (query, index) => {
    try { return (await query).map((address) => ({ address, family: index === 0 ? 4 : 6 })); }
    catch (error) {
      if (error && typeof error === "object" && "code" in error && ["ENODATA", "ENOTFOUND"].includes(String(error.code))) return [];
      throw error;
    }
  }));
  return answers.flat();
}

/**
 * Workers only: requires global_fetch_strictly_public and public global fetch.
 * Cloudflare's network boundary prevents private-network access even if DNS
 * changes after our additional A/AAAA check. That check is not IP pinning.
 * Never substitute Node fetch or a private-network/service binding here.
 * https://developers.cloudflare.com/workers/configuration/compatibility-flags/#global-fetch-strictly-public
 * https://blog.cloudflare.com/workers-environment-live-object-bindings/
 */
export async function readWorkersPublicResource(
  value: string, kind: Kind, deadline: number,
  dependencies: {
    resolve?: (host: string) => Promise<Address[]>;
    fetch?: PreviewFetch;
  } = {},
) {
  if (!dependencies.fetch && !isWorkersRuntime()) throw new Error("Workers preview transport requires Workers runtime");
  const request = dependencies.fetch || ((url: string, init: RequestInit) => globalThis.fetch(url, init));
  const limit = kind === "html" ? 1024 * 1024 : 512 * 1024;
  let url = previewTarget(value);
  for (let redirect = 0; redirect <= 3; redirect++) {
    if (Date.now() >= deadline) throw new Error("Preview timed out");
    // Reject mixed public/private answers and recheck every redirect hostname.
    await beforeDeadline(resolvePreviewAddress(url, dependencies.resolve || resolveWorkersPreviewAddresses), deadline);
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(new Error("Preview timed out")), Math.max(1, deadline - Date.now()));
    let response: Response | undefined;
    let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
    try {
      response = await beforeDeadline(request(url.href, {
        method: "GET", redirect: "manual", credentials: "omit", cache: "no-store", signal: controller.signal,
        headers: {
          "user-agent": "Shortwave-Preview/1.0",
          accept: kind === "html" ? "text/html,application/xhtml+xml" : "image/png,image/jpeg,image/gif,image/webp",
          "accept-encoding": "identity",
        },
      }), deadline);
      const location = response.headers.get("location");
      if ([301, 302, 303, 307, 308].includes(response.status) && location) {
        url = previewTarget(new URL(location, url).href);
        continue;
      }
      const type = (response.headers.get("content-type") || "").split(";")[0].trim().toLowerCase();
      const allowed = kind === "html" ? ["text/html", "application/xhtml+xml"] : ["image/png", "image/jpeg", "image/gif", "image/webp"];
      if (!response.ok || !allowed.includes(type) || !response.body || Number(response.headers.get("content-length") || 0) > limit) throw new Error("Unsupported preview response");
      // Reading a fetched body makes Workers decode its content encoding.
      // Count actual decoded bytes; Content-Length alone is not a size limit.
      const body = Buffer.alloc(limit);
      let size = 0;
      reader = response.body.getReader();
      while (true) {
        const chunk = await beforeDeadline(reader.read(), deadline);
        if (chunk.done) return { body: Buffer.from(body.subarray(0, size)), type, url };
        if (size + chunk.value.byteLength > limit) throw new Error("Preview response too large");
        body.set(chunk.value, size);
        size += chunk.value.byteLength;
      }
    } finally {
      clearTimeout(timer);
      controller.abort();
      if (reader) await reader.cancel().catch(() => {});
      else await response?.body?.cancel().catch(() => {});
    }
  }
  throw new Error("Too many preview redirects");
}
