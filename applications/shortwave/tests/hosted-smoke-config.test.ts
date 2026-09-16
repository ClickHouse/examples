import assert from "node:assert/strict";
import test from "node:test";
import { httpsOrigin, smokeAccountId, smokeServices, receiptLinkIds } from "../scripts/hosted-smoke-config";

function withEnvironment(values: Record<string, string | undefined>, check: () => void) {
  const previous = Object.fromEntries(Object.keys(values).map((key) => [key, process.env[key]]));
  try {
    for (const [key, value] of Object.entries(values)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
    check();
  } finally {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

test("hosted smoke requires an explicitly selected account", () => {
  for (const account of [undefined, "", "all", "account-id"]) {
    withEnvironment({ SMOKE_ACCOUNT_ID: account }, () => assert.throws(smokeAccountId));
  }
  const account = "9533d080-9b85-43c1-92ad-660d2cf84e63";
  withEnvironment({ SMOKE_ACCOUNT_ID: account }, () => assert.equal(smokeAccountId(), account));
});

test("hosted smoke only accepts HTTPS origins without URL credentials or paths", () => {
  for (const origin of [undefined, "http://example.com", "https://user:secret@example.com", "https://example.com/path", "https://example.com:8443", "https://example.com/?token=secret", "https://example.com/#fragment"]) {
    withEnvironment({ SMOKE_CUSTOM_ORIGIN: origin }, () => assert.throws(() => httpsOrigin("SMOKE_CUSTOM_ORIGIN")));
  }
  withEnvironment({ SMOKE_CUSTOM_ORIGIN: "https://example.com/" }, () => {
    assert.equal(httpsOrigin("SMOKE_CUSTOM_ORIGIN"), "https://example.com");
  });
});

test("receipt service scope includes databases and excludes connection credentials", () => {
  withEnvironment({
    DATABASE_URL: "postgresql://runtime:private-password@pg.example.com:5432/shortwave?sslmode=verify-full",
    CLICKHOUSE_URL: "https://default:private-password@ch.example.com:8443/",
    CLICKHOUSE_DATABASE: "events",
  }, () => {
    assert.deepEqual(smokeServices(), {
      postgres: "pg.example.com:5432/shortwave",
      clickhouse: "https://ch.example.com:8443",
      database: "events",
    });
    assert.equal(JSON.stringify(smokeServices()).includes("private-password"), false);
  });
});

test("cleanup requires receipt account and every service field to match", () => {
  const account = "9533d080-9b85-43c1-92ad-660d2cf84e63";
  const link = "da4ab17f-428d-4f1e-bc2e-e1ea2d9609c4";
  const services = { postgres: "pg.example.com/app", clickhouse: "https://ch.example.com", database: "events" };
  const receipt = { kind: "shortwave-hosted-smoke", accountId: account, services, linkIds: [link] };
  assert.deepEqual(receiptLinkIds(receipt, account, services), [link]);
  assert.deepEqual(receiptLinkIds({ ...receipt, linkIds: [] }, account, services), []);
  for (const invalid of [
    null,
    { ...receipt, accountId: link },
    { ...receipt, kind: "other" },
    { ...receipt, services: undefined },
    ...Object.keys(services).map((key) => ({ ...receipt, services: { ...services, [key]: "other" } })),
    { ...receipt, linkIds: [link, link] },
    { ...receipt, linkIds: ["not-a-uuid"] },
  ]) assert.throws(() => receiptLinkIds(invalid, account, services));
});
