// Local workerd smoke entrypoint. Run with a temporary Wrangler configuration;
// this script is not imported by or deployed with the application Worker.
import { readWorkersPublicResource, resolveWorkersPreviewAddresses } from "../src/server/preview-workers";
import { parsePreviewMetadata } from "../src/server/preview";
import { checkDomainTxt } from "../src/server/custom-domains";
import { createWorkersRuntime, runWorkersRuntime } from "../src/server/runtime";

export default {
  async fetch(_request: Request, env: Env) {
    return runWorkersRuntime(createWorkersRuntime(env), async () => {
    const results: Record<string, unknown> = {};
    results.dnsOwnership = await checkDomainTxt("_shortwave-verification.example.com", "smoke-nonmatching-value");
    results.googleAddresses = await resolveWorkersPreviewAddresses("www.google.com");
    results.badsslAddresses = await resolveWorkersPreviewAddresses("wrong.host.badssl.com");
    for (const [name, url] of [
      ["publicHttps", "https://www.google.com/"],
      ["wrongCertificate", "https://wrong.host.badssl.com/"],
      ["privateIp", "http://127.0.0.1/"],
    ]) {
      try {
        const page = await readWorkersPublicResource(url, "html", Date.now() + 10_000, {
          fetch: async (target, options) => {
            const response = await globalThis.fetch(target, options);
            results[`${name}Http`] = {
              status: response.status,
              type: response.headers.get("content-type"),
              length: response.headers.get("content-length"),
              server: response.headers.get("server"),
            };
            return response;
          },
        });
        results[name] = { status: "ready", title: parsePreviewMetadata(page.body.toString("utf8"), page.url).title };
      } catch (error) {
        results[name] = { status: "rejected", message: error instanceof Error ? error.message : "Preview failed" };
      }
    }
    return Response.json(results);
    });
  },
};
