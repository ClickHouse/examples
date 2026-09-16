import { test } from "node:test";
import assert from "node:assert/strict";
import { readWorkersPublicResource } from "../src/server/preview-workers";

const resolve = async () => [{ address: "8.8.8.8", family: 4 }];
const html = (body = "<title>Hello</title>") => new Response(body, { headers: { "content-type": "text/html; charset=utf-8" } });

test("Workers preview fetch is runtime-scoped and sends only explicit unauthenticated request fields", async () => {
  await assert.rejects(readWorkersPublicResource("https://example.com", "html", Date.now() + 1000), /requires Workers runtime/);
  const result = await readWorkersPublicResource("https://example.com/path#fragment", "html", Date.now() + 1000, {
    resolve,
    fetch: async (url, options) => {
      assert.equal(url, "https://example.com/path");
      assert.equal(options.redirect, "manual");
      assert.equal(options.credentials, "omit");
      assert.equal(options.cache, "no-store");
      assert.equal(options.method, "GET");
      const headers = new Headers(options.headers);
      assert.equal(headers.has("cookie"), false);
      assert.equal(headers.has("authorization"), false);
      assert.equal(headers.has("referer"), false);
      assert.ok(options.signal);
      return html();
    },
  });
  assert.equal(result.body.toString(), "<title>Hello</title>");
  assert.equal(result.type, "text/html");
});

test("Workers DNS validation rejects private and mixed-family answers before fetch", async () => {
  let fetched = false;
  for (const addresses of [[], [{ address: "127.0.0.1", family: 4 }], [{ address: "8.8.8.8", family: 4 }, { address: "::1", family: 6 }]]) {
    await assert.rejects(readWorkersPublicResource("https://example.com", "html", Date.now() + 1000, {
      resolve: async () => addresses,
      fetch: async () => { fetched = true; return html(); },
    }), /Private preview address/);
  }
  assert.equal(fetched, false);
});

test("Workers redirects are manual, cancel unused bodies, recheck DNS and reject private targets", async () => {
  let canceled = 0;
  let calls = 0;
  let resolutions = 0;
  const redirect = (location: string) => new Response(new ReadableStream({ cancel() { canceled++; } }), { status: 302, headers: { location } });
  await assert.rejects(readWorkersPublicResource("https://example.com", "html", Date.now() + 1000, {
    resolve: async () => [{ address: ++resolutions === 1 ? "8.8.8.8" : "127.0.0.1", family: 4 }],
    fetch: async () => { calls++; return redirect("/again"); },
  }), /Private preview address/);
  assert.equal(calls, 1);
  assert.equal(resolutions, 2);
  assert.equal(canceled, 1);
  for (const location of ["//169.254.169.254/secret", "file:///etc/passwd", "https://user:password@example.com/"]) {
    await assert.rejects(readWorkersPublicResource("https://example.com", "html", Date.now() + 1000, {
      resolve, fetch: async () => redirect(location),
    }));
  }
  calls = 0;
  await assert.rejects(readWorkersPublicResource("https://example.com", "html", Date.now() + 1000, {
    resolve, fetch: async () => { calls++; return redirect("/again"); },
  }), /Too many preview redirects/);
  assert.equal(calls, 4);
});

test("Workers response checks MIME/status and bounds actual decoded bytes despite misleading length", async () => {
  for (const response of [new Response("error", { status: 500 }), new Response("<svg/>", { headers: { "content-type": "image/svg+xml" } }), new Response("small", { headers: { "content-type": "text/html", "content-length": "1048577" } })]) {
    await assert.rejects(readWorkersPublicResource("https://example.com", "html", Date.now() + 1000, { resolve, fetch: async () => response }), /Unsupported preview response/);
  }
  for (const kind of ["html", "image"] as const) {
    let canceled = false;
    const response = new Response(new ReadableStream({
      start(controller) { controller.enqueue(new Uint8Array((kind === "html" ? 1024 : 512) * 1024 + 1)); },
      cancel() { canceled = true; },
    }), { headers: { "content-type": kind === "html" ? "text/html" : "image/png", "content-length": "1", "content-encoding": "gzip" } });
    // The injected stream represents the decoded body exposed by Workers.
    await assert.rejects(readWorkersPublicResource("https://example.com", kind, Date.now() + 1000, { resolve, fetch: async () => response }), /too large/);
    assert.equal(canceled, true);
  }
});

test("Workers total deadline aborts stalled headers, body and DNS without another fetch", async () => {
  let signal: AbortSignal | null | undefined;
  await assert.rejects(readWorkersPublicResource("https://example.com", "html", Date.now() + 30, {
    resolve, fetch: async (_url, options) => { signal = options.signal; return new Promise(() => {}); },
  }), /timed out/);
  assert.equal(signal?.aborted, true);
  let canceled = false;
  await assert.rejects(readWorkersPublicResource("https://example.com", "html", Date.now() + 30, {
    resolve, fetch: async () => new Response(new ReadableStream({ cancel() { canceled = true; } }), { headers: { "content-type": "text/html" } }),
  }), /timed out/);
  assert.equal(canceled, true);
  let fetched = false;
  await assert.rejects(readWorkersPublicResource("https://example.com", "html", Date.now() + 30, {
    resolve: () => new Promise(() => {}), fetch: async () => { fetched = true; return html(); },
  }), /timed out/);
  assert.equal(fetched, false);
});

test("Workers transport preserves platform TLS failure without retrying an unsafe transport", async () => {
  let calls = 0;
  await assert.rejects(readWorkersPublicResource("https://example.com", "html", Date.now() + 1000, {
    resolve, fetch: async () => { calls++; throw new Error("TLS certificate verification failed"); },
  }), /TLS certificate verification failed/);
  assert.equal(calls, 1);
});
