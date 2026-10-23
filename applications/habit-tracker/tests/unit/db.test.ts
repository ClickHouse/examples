import assert from "node:assert/strict";
import test from "node:test";
import { poolConfig, tlsOptions } from "../../src/db";

test("a remote database without a CA is refused, not connected in plaintext", () => {
  assert.throws(
    () =>
      tlsOptions("postgres://app:pw@db.example.com:5432/postgres", undefined),
    /PGSSLROOTCERT/,
  );
});

test("local Postgres without TLS is allowed", () => {
  assert.equal(
    tlsOptions("postgres://app:pw@127.0.0.1:5432/postgres", undefined),
    false,
  );
  assert.equal(
    tlsOptions("postgres://app:pw@localhost:5433/postgres", undefined),
    false,
  );
});

test("sslmode in the URL is rejected because it would override the CA", () => {
  assert.throws(
    () =>
      poolConfig({
        DATABASE_URL: "postgres://app:pw@localhost/postgres?sslmode=require",
      }),
    /query parameters/,
  );
});
