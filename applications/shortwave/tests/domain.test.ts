import { test } from "node:test";
import assert from "node:assert/strict";
import {
  contrastRatio,
  defaultQrStyle,
  linkInputSchema,
  mergeUtm,
  qrStyleSchema,
  requestDimensions,
  validateDestination,
  validateSlug,
} from "../src/lib/domain";
import { CLICKHOUSE_QR_IMAGE, CLICKHOUSE_QR_LOGO, qrLogoImage } from "../src/lib/qr-logo";

test("destinations permit web URLs and reject executable schemes, credentials and controls", () => {
  assert.equal(
    validateDestination("https://example.com/path?q=1#anchor"),
    "https://example.com/path?q=1#anchor",
  );
  for (const invalid of [
    "javascript:alert(1)",
    "data:text/html,x",
    "file:///etc/passwd",
    "https://user:secret@example.com",
    "/relative",
    "https://example.com/\npath",
  ]) {
    assert.throws(() => validateDestination(invalid), Error, invalid);
  }
});

test("destinations default omitted protocols to HTTPS while preserving explicit web protocols", () => {
  for (const [input, expected] of [
    ["example.com", "https://example.com/"],
    ["example.com/path?q=1#anchor", "https://example.com/path?q=1#anchor"],
    ["  www.example.com/path  ", "https://www.example.com/path"],
    ["example.com:8443/path", "https://example.com:8443/path"],
    ["//example.com/path", "https://example.com/path"],
    ["//example.com:8443/path", "https://example.com:8443/path"],
    ["localhost:4317/path", "https://localhost:4317/path"],
    ["127.0.0.1:4317/path", "https://127.0.0.1:4317/path"],
    ["[::1]:4317/path", "https://[::1]:4317/path"],
    ["http://example.com/path", "http://example.com/path"],
    ["HTTPS://EXAMPLE.COM/path", "https://example.com/path"],
  ]) assert.equal(validateDestination(input!), expected, input);
  assert.equal(linkInputSchema.parse({ destination: "example.com/path" }).destination, "https://example.com/path");
  assert.equal(mergeUtm("example.com/path?x=1#here", { source: "newsletter" }).resolvedUrl,
    "https://example.com/path?x=1&utm_source=newsletter#here");
});

test("omitted-protocol handling rejects ambiguous schemes, credentials and relative paths", () => {
  for (const invalid of [
    "", "   ", "/relative", "./relative", "../relative", "docs/setup", "?query=1", "#anchor", "///example.com",
    "javascript:443", "javascript://example.com", "data:443", "file:443", "ftp://example.com", "mailto:user@example.com",
    "https:example.com", "intranet:443", "example.com:invalid/path", "example.com:99999/path",
    "user:secret@example.com", "user@example.com", "//user:secret@example.com",
    "example.com/\npath", "example.com/\tpath", "example.com/\u0000path", "example.com\\path",
    `example.com/${"x".repeat(4096)}`,
  ]) assert.throws(() => validateDestination(invalid), Error, invalid);
});

test("UTMs replace explicitly supplied keys, preserve other params and fragments, and snapshot existing UTMs", () => {
  const result = mergeUtm(
    "https://example.com/?utm_source=old&utm_medium=email&x=a%26b#here",
    { source: "new campaign", campaign: "launch" },
  );
  const url = new URL(result.resolvedUrl);
  assert.equal(url.searchParams.get("utm_source"), "new campaign");
  assert.equal(url.searchParams.get("x"), "a&b");
  assert.equal(url.hash, "#here");
  assert.deepEqual(result.utm, {
    source: "new campaign",
    medium: "email",
    campaign: "launch",
  });
});

test("empty UTM values remove preexisting values and applied template copies do not mutate", () => {
  const template = { source: "email", campaign: "spring" };
  const result = mergeUtm("https://example.com/?utm_content=old", {
    ...template,
    content: "",
  });
  template.campaign = "summer";
  assert.equal(result.utm.campaign, "spring");
  assert.equal(
    new URL(result.resolvedUrl).searchParams.has("utm_content"),
    false,
  );
});

test("inherited UTM values respect editable limits and may be replaced or removed", () => {
  const destination = `https://example.com/?utm_campaign=${"x".repeat(201)}`;
  assert.throws(() => mergeUtm(destination));
  assert.equal(
    mergeUtm(destination, { campaign: "replacement" }).utm.campaign,
    "replacement",
  );
  assert.deepEqual(mergeUtm(destination, { campaign: "" }).utm, {});
});

test("custom slug rules exclude path separators, short names and encoded routing escapes", () => {
  assert.equal(validateSlug("launch-2026_X"), "launch-2026_X");
  for (const slug of [
    "ab",
    "../admin",
    "a/b",
    "%2fadmin",
    "has space",
    "-first",
    "a".repeat(49),
  ])
    assert.throws(() => validateSlug(slug));
});

test("link inputs discard duplicate tags and reject browser-supplied account scope", () => {
  assert.deepEqual(
    linkInputSchema.parse({
      destination: "https://example.com",
      tags: ["launch", "launch", "web"],
    }).tags,
    ["launch", "web"],
  );
  assert.throws(() =>
    linkInputSchema.parse({
      destination: "https://example.com",
      accountId: "another-account",
    }),
  );
});

test("QR styles enforce contrast and raster-only logo data", () => {
  assert.equal(contrastRatio("#000000", "#ffffff"), 21);
  const good = {
    foreground: "#000000",
    background: "#ffffff",
    dots: "square",
    logo: null,
  };
  assert.doesNotThrow(() => qrStyleSchema.parse(good));
  assert.throws(() => qrStyleSchema.parse({ ...good, foreground: "#eeeeee" }));
  assert.throws(() =>
    qrStyleSchema.parse({
      ...good,
      logo: "data:image/svg+xml;base64,PHN2Zz4=",
    }),
  );
  assert.throws(() =>
    qrStyleSchema.parse({ ...good, logo: "https://example.com/logo.png" }),
  );
});

test("QR defaults and legacy missing logos use the trusted ClickHouse SVG while custom rasters survive", () => {
  assert.equal(defaultQrStyle.logo, CLICKHOUSE_QR_LOGO);
  assert.equal(qrStyleSchema.parse(defaultQrStyle).logo, CLICKHOUSE_QR_LOGO);
  assert.equal(qrLogoImage(CLICKHOUSE_QR_LOGO), CLICKHOUSE_QR_IMAGE);
  assert.match(CLICKHOUSE_QR_IMAGE, /^data:image\/svg\+xml,/);
  assert.match(decodeURIComponent(CLICKHOUSE_QR_IMAGE.split(",")[1]!), /<svg.*<path/);
  for (const logo of [null, undefined]) {
    assert.equal(qrStyleSchema.parse({ ...defaultQrStyle, logo }).logo, CLICKHOUSE_QR_LOGO);
    assert.equal(qrLogoImage(logo), CLICKHOUSE_QR_IMAGE);
  }
  const raster = "data:image/png;base64,iVBORw0KGgo=";
  assert.equal(qrStyleSchema.parse({ ...defaultQrStyle, logo: raster }).logo, raster);
  assert.equal(qrLogoImage(raster), raster);
  for (const logo of [CLICKHOUSE_QR_IMAGE, "data:image/svg+xml;base64,PHN2Zz4=", "https://clickhouse.com/logo.svg", "another-builtin"]) {
    assert.throws(() => qrStyleSchema.parse({ ...defaultQrStyle, logo }));
  }
});

test("built-in QR logo stays transparent and chooses the higher-contrast black or white bars", () => {
  for (const background of ["#ffffff", "#000000", "#171717", "#777777", "#757575", "#faff69", "#ff0000", "#0000ff"]) {
    const svg = decodeURIComponent(qrLogoImage(CLICKHOUSE_QR_LOGO, background)!.split(",")[1]!);
    assert.doesNotMatch(svg, /<rect|background|#ff0\b/i);
    const expected = contrastRatio("#000000", background) >= contrastRatio("#ffffff", background) ? "#000000" : "#ffffff";
    assert.match(svg, new RegExp(`fill="${expected}"`));
    assert.equal((svg.match(/<path /g) ?? []).length, 5);
  }
  assert.equal(qrLogoImage(null, "#000000"), qrLogoImage(CLICKHOUSE_QR_LOGO, "#000000"));
  const raster = "data:image/png;base64,iVBORw0KGgo=";
  assert.equal(qrLogoImage(raster, "#000000"), raster);
});

test("traffic metadata drops referrer paths and never derives country from untrusted input", () => {
  const dimensions = requestDimensions(
    "https://example.com/private?token=secret",
    "ExampleBot/1.0",
  );
  assert.equal(dimensions.referrer_domain, "example.com");
  assert.equal(dimensions.is_bot, 1);
  assert.equal(dimensions.country, "Unknown");
  assert.equal(requestDimensions("not a URL").referrer_domain, "");
});
