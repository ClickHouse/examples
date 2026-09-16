import { test } from "node:test";
import assert from "node:assert/strict";
import { MAX_CUSTOM_DOMAIN_LENGTH } from "../src/lib/custom-domains";
import { checkDomainTxt, normalizeCustomDomain, type TxtResolver } from "../src/server/custom-domains";

const name = "_shortwave-verification.links.shortwave.dev";
const value = "shortwave-verification=0123456789";
const resolver = (resolveTxt: TxtResolver["resolveTxt"]) => ({ createResolver: () => ({ resolveTxt, cancel() {} }) });

test("custom domains normalize case, IDNs and a trailing root dot", () => {
  assert.equal(normalizeCustomDomain(" Links.Shortwave.Dev. "), "links.shortwave.dev");
  assert.equal(normalizeCustomDomain("bücher.de"), "xn--bcher-kva.de");
  assert.equal(normalizeCustomDomain("xn--bcher-kva.de"), "xn--bcher-kva.de");
  assert.equal(normalizeCustomDomain("a.b"), "a.b");
  const boundary = `${"a".repeat(63)}.${"b".repeat(63)}.${"c".repeat(63)}.${"d".repeat(33)}.dev`;
  assert.equal(boundary.length, MAX_CUSTOM_DOMAIN_LENGTH);
  assert.equal(normalizeCustomDomain(boundary), boundary);
  assert.throws(() => normalizeCustomDomain(boundary.replace(".dev", "d.dev")));
});

test("custom domains reject URL syntax, malformed labels, addresses and reserved names", () => {
  assert.throws(() => normalizeCustomDomain("foo.alt"));
  for (const hostname of ["", "https://shortwave.dev", "shortwave.dev/path", "shortwave.dev:443", "shortwave.dev?x", "shortwave.dev#x", "me@shortwave.dev", "*.shortwave.dev", "_test.shortwave.dev", "shortwave..dev", "-links.shortwave.dev", "links-.shortwave.dev", "shortwave.dev..", "shortwave. dev", "shortwave.dev\n/path", "shortwave\\dev", "shortwave%2edev", "127.0.0.1", "127.1", "0x7f.1", "2130706433", "[::1]", "::1", "localhost", "foo.localhost", "foo.local", "foo.internal", "foo.test", "foo.invalid", "foo.example", "foo.onion", "foo.arpa", "example.com", "a.example.net", "example.org", "foo.123", `${"a".repeat(64)}.dev`, `${"a".repeat(63)}.${"b".repeat(63)}.${"c".repeat(63)}.${"d".repeat(35)}.com`]) {
    assert.throws(() => normalizeCustomDomain(hostname), Error, hostname);
  }
});

test("DNS ownership joins chunks within a record and matches the exact value", async () => {
  let queried = "";
  assert.deepEqual(await checkDomainTxt(name, value, resolver(async (hostname) => {
    queried = hostname;
    return [["unrelated"], ["shortwave-verification=", "0123456789"]];
  })), { outcome: "match", error: null });
  assert.equal(queried, `${name}.`);
  for (const answers of [[["shortwave-verification="], ["0123456789"]], [[`${value} `]], [[`"${value}"`]], [[value.toUpperCase()]], [[`prefix${value}`]]]) {
    assert.equal((await checkDomainTxt(name, value, resolver(async () => answers))).outcome, "mismatch");
  }
});

test("DNS absence is definitive while server and transport errors remain temporary", async () => {
  assert.equal((await checkDomainTxt(name, value, resolver(async () => []))).outcome, "missing");
  for (const code of ["ENOTFOUND", "ENODATA", "ESERVFAIL", "ETIMEOUT", "ECONNREFUSED", "ECANCELLED", "EREFUSED"]) {
    const result = await checkDomainTxt(name, value, resolver(async () => { throw Object.assign(new Error("internal details"), { code }); }));
    assert.equal(result.outcome, ["ENOTFOUND", "ENODATA"].includes(code) ? "missing" : "unavailable");
    assert.doesNotMatch(result.error!, /internal details/);
  }
});

test("DNS deadline cancels only its own resolver and returns a temporary error", async () => {
  let canceled = 0;
  const result = await checkDomainTxt(name, value, {
    timeoutMs: 5,
    createResolver: () => ({ resolveTxt: () => new Promise(() => {}), cancel: () => { canceled++; } }),
  });
  assert.equal(result.outcome, "unavailable");
  assert.equal(canceled, 1);
  let successCanceled = false;
  await checkDomainTxt(name, value, { timeoutMs: 5, createResolver: () => ({ resolveTxt: async () => [[value]], cancel: () => { successCanceled = true; } }) });
  await new Promise((resolve) => setTimeout(resolve, 10));
  assert.equal(successCanceled, false);
});
