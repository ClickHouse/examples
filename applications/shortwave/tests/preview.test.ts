import { test } from "node:test";
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { PassThrough } from "node:stream";
import type { ClientRequest, IncomingMessage, RequestOptions, request } from "node:http";
import { destinationPreview, imageData, isPublicAddress, parsePreviewMetadata, previewTarget, readPublicResource, resolvePreviewAddress } from "../src/server/preview";

test("preview fetching rejects local, mapped, reserved and non-web destinations", () => {
  for (const address of ["127.0.0.1", "0.0.0.0", "10.1.2.3", "169.254.169.254", "172.16.0.1", "192.168.1.1", "100.64.0.1", "198.19.0.1", "192.0.2.1", "224.0.0.1", "::1", "::ffff:127.0.0.1", "64:ff9b::7f00:1", "fc00::1", "fe80::1", "2001:db8::1", "2002:7f00:1::", "3fff::1"]) assert.equal(isPublicAddress(address), false, address);
  for (const address of ["8.8.8.8", "1.1.1.1", "2606:4700:4700::1111", "2001:4860:4860::8888"]) assert.equal(isPublicAddress(address), true, address);
  for (const url of ["file:///etc/passwd", "https://user:secret@example.com", "http://2130706433", "http://0x7f000001", "https://[::ffff:127.0.0.1]", "https://example.com:444/", "https://example.com/\npath"]) assert.throws(() => previewTarget(url), Error, url);
  assert.equal(previewTarget("https://example.com:443/path#fragment").href, "https://example.com/path");
});

test("preview DNS validation rejects mixed public/private answers and pins checked address", async () => {
  const url = previewTarget("https://example.com");
  await assert.rejects(resolvePreviewAddress(url, async () => [{ address: "8.8.8.8", family: 4 }, { address: "127.0.0.1", family: 4 }]));
  await assert.rejects(resolvePreviewAddress(url, async () => []));
  assert.deepEqual(await resolvePreviewAddress(url, async () => [{ address: "1.1.1.1", family: 4 }]), { address: "1.1.1.1", family: 4 });
  await assert.rejects(destinationPreview("", "https://example.com"), /sign in/);
  assert.equal((await destinationPreview("test-user", "http://127.0.0.1")).status, "unavailable");
});

test("OG metadata keeps first values, decodes entities, resolves images and ignores script/comment decoys", () => {
  const metadata = parsePreviewMetadata(`<head><!-- <meta property="og:title" content="bad"> --><script>const x='<meta property="og:title" content="bad">';</script><title>Fallback</title><meta content='Launch &amp; learn &#x1f680;' property='og:title'><meta property="og:title" content="second"><meta name="description" content="Fallback description"><meta property="og:description" content="A &quot;preview&quot; &gt; a URL"><meta property="og:image" content="../image.png?a=1&amp;b=2"><meta property="og:image:alt" content="The launch"></head>`, new URL("https://example.com/blog/page"));
  assert.equal(metadata.title, "Launch & learn 🚀");
  assert.equal(metadata.description, 'A "preview" > a URL');
  assert.equal(metadata.imageUrl, "https://example.com/image.png?a=1&b=2");
  assert.equal(metadata.imageAlt, "The launch");
  assert.equal(parsePreviewMetadata('<title>Fallback &amp; title</title><meta property="og:image" content="http://127.0.0.1/secret">', new URL("https://example.com")).imageUrl, null);
  assert.equal(parsePreviewMetadata('<title>Fallback &amp; title</title>', new URL("https://example.com")).title, "Fallback & title");
});

test("preview images allow bounded raster data with matching signatures and never SVG or external URLs", () => {
  const png = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  assert.match(imageData(png, "image/png")!, /^data:image\/png;base64,/);
  assert.equal(imageData(png, "image/jpeg"), null);
  assert.equal(imageData(Buffer.from('<svg onload="alert(1)"/>'), "image/svg+xml"), null);
  assert.equal(imageData(Buffer.from('<svg onload="alert(1)"/>'), "image/png"), null);
  assert.equal(imageData(Buffer.alloc(512 * 1024 + 1), "image/png"), null);
});

function transport(reply: (url: URL, options: RequestOptions, response: IncomingMessage & PassThrough) => void) {
  const calls: URL[] = [];
  const mock = ((url: URL, options: RequestOptions, callback: (response: IncomingMessage) => void) => {
    calls.push(url);
    const emitter = new EventEmitter();
    const req = Object.assign(emitter, {
      end() {
        queueMicrotask(() => {
          const response = Object.assign(new PassThrough(), { statusCode: 200, headers: { "content-type": "text/html" } }) as IncomingMessage & PassThrough;
          response.on("close", () => emitter.emit("close"));
          // Configure headers before the response callback; body arrives later.
          reply(url, options, response);
          callback(response);
        });
        return req;
      },
      destroy(error?: Error) { if (error) emitter.emit("error", error); emitter.emit("close"); return req; },
    });
    return req as unknown as ClientRequest;
  }) as unknown as typeof request;
  return { calls, request: mock, resolve: async () => [{ address: "1.1.1.1", family: 4 }] };
}

test("request boundary pins DNS and rechecks same-host redirects against rebinding", async () => {
  let resolutions = 0;
  let pinned = false;
  const mock = transport((_url, options, response) => {
    assert.equal(options.agent, false);
    assert.equal(options.family, 4);
    assert.equal((options.headers as Record<string, string>)["accept-encoding"], "identity");
    options.lookup!("example.com", { family: 4 }, (error, address, family) => {
      assert.equal(error, null);
      assert.equal(address, "1.1.1.1");
      assert.equal(family, 4);
      pinned = true;
    });
    response.statusCode = 302;
    response.headers.location = "/redirect";
  });
  await assert.rejects(readPublicResource("https://example.com", "html", Date.now() + 1000, {
    ...mock, resolve: async () => [{ address: ++resolutions === 1 ? "1.1.1.1" : "127.0.0.1", family: 4 }],
  }), /Private preview address/);
  assert.equal(pinned, true);
  assert.equal(mock.calls.length, 1);
  assert.equal(resolutions, 2);
});

test("private redirects are rejected before opening another connection and public redirects are bounded", async () => {
  const privateRedirect = transport((_url, _options, response) => {
    response.statusCode = 302;
    response.headers.location = "http://169.254.169.254/latest/meta-data";
  });
  await assert.rejects(readPublicResource("https://example.com", "html", Date.now() + 1000, privateRedirect), /Private preview URL/);
  assert.equal(privateRedirect.calls.length, 1);
  const loop = transport((_url, _options, response) => {
    response.statusCode = 301;
    response.headers.location = "/again";
  });
  await assert.rejects(readPublicResource("https://example.com", "html", Date.now() + 1000, loop), /Too many preview redirects/);
  assert.equal(loop.calls.length, 4);
});

test("request boundary enforces response bytes, content types and total deadline", async () => {
  const oversized = transport((_url, _options, response) => { queueMicrotask(() => response.end(Buffer.alloc(1024 * 1024 + 1))); });
  await assert.rejects(readPublicResource("https://example.com", "html", Date.now() + 1000, oversized), /too large/);
  const svg = transport((_url, _options, response) => { response.headers["content-type"] = "image/svg+xml"; });
  await assert.rejects(readPublicResource("https://example.com/image", "image", Date.now() + 1000, svg), /Unsupported preview response/);
  const oversizedImage = transport((_url, _options, response) => {
    response.headers["content-type"] = "image/png";
    queueMicrotask(() => response.end(Buffer.alloc(512 * 1024 + 1)));
  });
  await assert.rejects(readPublicResource("https://example.com/image", "image", Date.now() + 1000, oversizedImage), /too large/);
  const stalled = transport(() => {});
  await assert.rejects(readPublicResource("https://example.com", "html", Date.now() + 30, stalled), /timed out/);
  const stalledDns = transport(() => {});
  await assert.rejects(readPublicResource("https://example.com", "html", Date.now() + 30, { ...stalledDns, resolve: () => new Promise(() => {}) }), /timed out/);
  assert.equal(stalledDns.calls.length, 0);
});
