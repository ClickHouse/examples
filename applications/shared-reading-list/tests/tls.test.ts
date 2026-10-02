import { test } from "node:test";
import assert from "node:assert/strict";
import postgres from "postgres";
import { readFileSync } from "node:fs";
import { connect } from "../src/lib/server/connection";
const url = process.env.DATABASE_URL!;
test("verified CA and hostname connect", async () => {
  const c = connect();
  try {
    assert.equal((await c`SELECT 1 AS ok`)[0].ok, 1);
  } finally {
    await c.end();
  }
});
test("unrelated CA is rejected", async () => {
  const c = connect(
    url,
    process.env.WRONG_CA_PATH ?? "/etc/ssl/certs/ca-certificates.crt",
  );
  try {
    await assert.rejects(c`SELECT 1`, (e) =>
      /certificate|issuer|verify/i.test(String(e)),
    );
  } finally {
    await c.end();
  }
});
test("wrong TLS hostname is rejected", async () => {
  const c = postgres(url, {
    max: 1,
    connect_timeout: 10,
    ssl: {
      ca: readFileSync(process.env.DATABASE_CA_PATH!, "utf8"),
      rejectUnauthorized: true,
      servername: "wrong.example.invalid",
    },
  });
  try {
    await assert.rejects(
      c`SELECT 1`,
      (e) => (e as { code: string }).code === "ERR_TLS_CERT_ALTNAME_INVALID",
    );
  } finally {
    await c.end();
  }
});
