import { describe, expect, test } from "bun:test";
import type { SQL } from "bun";
import { createApp, MAX_BODY_BYTES } from "../src/app";
import { loadConfig } from "../src/config";

const token = "test-token-0123456789-abcdefghijklmnopqrstuvwxyz";
const environment = {
  DATABASE_URL: "postgres://example_user:example_password@db.example.invalid:5432/stock",
  PG_CA_CERT_PATH: "/example/ca.pem",
  API_KEYS_JSON: JSON.stringify({ "test-client": token }),
};

describe("configuration rejects ambiguous or insecure input", () => {
  test("defaults to localhost and a bounded pool", () => {
    const config = loadConfig(environment);
    expect(config.hostname).toBe("127.0.0.1");
    expect(config.port).toBe(3000);
    expect(config.database.maxConnections).toBe(5);
    expect(config.apiKeys.get("test-client")).toBe(token);
  });

  test("requires all connection and authentication fields", () => {
    for (const name of ["DATABASE_URL", "PG_CA_CERT_PATH", "API_KEYS_JSON"]) {
      expect(() => loadConfig({ ...environment, [name]: "" })).toThrow();
    }
  });

  test("rejects URL flags that could change TLS or be sent as server settings", () => {
    for (const suffix of ["?sslmode=disable", "?channel_binding=require", "#fragment"]) {
      expect(() => loadConfig({ ...environment, DATABASE_URL: environment.DATABASE_URL + suffix })).toThrow();
    }
    for (const url of [
      "not a url", "sqlite:///tmp/database.db", "https://example.invalid/db",
      "postgres://user@db.example.invalid/database", "postgres://user:password@db.example.invalid/",
    ]) {
      expect(() => loadConfig({ ...environment, DATABASE_URL: url })).toThrow();
    }
  });

  test("requires usable, unique tokens and bounded client IDs", () => {
    for (const value of [
      "invalid JSON", "null", "[]", "{}", JSON.stringify({ client: "short" }),
      JSON.stringify({ a: token, b: token }), JSON.stringify({ "bad client": token }),
      JSON.stringify({ ["x".repeat(65)]: token }),
      JSON.stringify({ client: "REPLACE_ME_WITH_A_RANDOM_TOKEN_OF_32_CHARACTERS" }),
      JSON.stringify({ client: "x".repeat(257) }),
    ]) {
      expect(() => loadConfig({ ...environment, API_KEYS_JSON: value })).toThrow();
    }
  });

  test("rejects invalid listen ports and unbounded pools", () => {
    for (const PORT of ["0", "65536", "1.5", "3000ignored", "-1"]) {
      expect(() => loadConfig({ ...environment, PORT })).toThrow();
    }
    for (const PG_MAX_CONNECTIONS of ["0", "21", "1.5", "5ignored", "-1"]) {
      expect(() => loadConfig({ ...environment, PG_MAX_CONNECTIONS })).toThrow();
    }
  });
});

function isolatedApp() {
  let databaseCalls = 0;
  const forbiddenQuery = () => {
    databaseCalls++;
    throw new Error("Validation reached the database unexpectedly.");
  };
  const sql = Object.assign(forbiddenQuery, { begin: forbiddenQuery }) as unknown as SQL;
  return {
    app: createApp({ sql, apiKeys: new Map([["test-client", token]]) }),
    calls: () => databaseCalls,
  };
}

function postHeaders(extra: Record<string, string> = {}): Record<string, string> {
  return {
    Authorization: `Bearer ${token}`,
    "Content-Type": "application/json",
    "Idempotency-Key": "unit-test-key",
    ...extra,
  };
}

describe("HTTP boundary validation needs no database", () => {
  test("every route rejects absent and incorrect authentication before querying", async () => {
    const { app, calls } = isolatedApp();
    for (const [path, method] of [
      ["/inventory", "GET"], ["/reservations", "POST"],
      [`/reservations/${crypto.randomUUID()}`, "GET"],
      [`/reservations/${crypto.randomUUID()}`, "DELETE"],
    ] as const) {
      for (const authorization of ["", "Basic user:password", `Bearer ${"x".repeat(40)}`]) {
        const response = await app.request(path, { method, headers: { Authorization: authorization } });
        expect(response.status).toBe(401);
        expect((await response.json()).error.code).toBe("unauthorized");
        expect(response.headers.get("WWW-Authenticate")).toBe("Bearer");
        expect(response.headers.get("Cache-Control")).toBe("no-store");
      }
    }
    expect(calls()).toBe(0);
  });

  test("rejects missing keys and non-JSON content", async () => {
    const { app, calls } = isolatedApp();
    const absentKey = postHeaders();
    delete absentKey["Idempotency-Key"];
    const keyResponse = await app.request("/reservations", {
      method: "POST", headers: absentKey, body: JSON.stringify({ sku: "BOOK", quantity: 1 }),
    });
    expect(keyResponse.status).toBe(400);
    expect((await keyResponse.json()).error.code).toBe("invalid_idempotency_key");
    const mediaResponse = await app.request("/reservations", {
      method: "POST", headers: postHeaders({ "Content-Type": "text/plain" }), body: "{}",
    });
    expect(mediaResponse.status).toBe(415);
    expect((await mediaResponse.json()).error.code).toBe("unsupported_media_type");
    expect(calls()).toBe(0);
  });

  test("rejects malformed JSON, invalid UTF-8, and client-supplied ownership", async () => {
    const { app, calls } = isolatedApp();
    for (const body of ["{", "", new Uint8Array([0xff, 0xfe])]) {
      const response = await app.request("/reservations", { method: "POST", headers: postHeaders(), body });
      expect(response.status).toBe(400);
      expect((await response.json()).error.code).toBe("invalid_json");
    }
    for (const body of [
      null, [], {}, { sku: "BOOK", quantity: 0 }, { sku: "BOOK", quantity: 1.2 },
      { sku: "BOOK", quantity: "2" }, { sku: "BOOK", quantity: 1001 },
      { sku: "BOOK", quantity: 1, client_id: "another-client" },
    ]) {
      const response = await app.request("/reservations", {
        method: "POST", headers: postHeaders(), body: JSON.stringify(body),
      });
      expect(response.status).toBe(400);
      expect((await response.json()).error.code).toBe("invalid_request");
    }
    expect(calls()).toBe(0);
  });

  test("counts streamed bytes even when Content-Length is absent or dishonest", async () => {
    const { app, calls } = isolatedApp();
    for (const extra of [{}, { "Content-Length": "1" }] as Record<string, string>[]) {
      const body = new ReadableStream<Uint8Array>({
        start(controller) {
          controller.enqueue(new Uint8Array(MAX_BODY_BYTES));
          controller.enqueue(new Uint8Array(1));
          controller.close();
        },
      });
      const response = await app.request("/reservations", {
        method: "POST", headers: postHeaders(extra), body,
      });
      expect(response.status).toBe(413);
      expect((await response.json()).error.code).toBe("body_too_large");
    }
    expect(calls()).toBe(0);
  });

  test("invalid identifiers and unknown routes return JSON without querying", async () => {
    const { app, calls } = isolatedApp();
    for (const [path, method] of [
      ["/reservations/invalid-id", "GET"], ["/reservations/invalid-id", "DELETE"],
      ["/missing-route", "GET"],
    ] as const) {
      const response = await app.request(path, { method, headers: postHeaders() });
      expect(response.status).toBe(404);
      expect((await response.json()).error.code).toBe("not_found");
    }
    expect(calls()).toBe(0);
  });

  test("unexpected errors return a retryable response without leaking connection details", async () => {
    const failure = new Error("postgres://user:private-password@private-endpoint/database");
    const sql = (() => { throw failure; }) as unknown as SQL;
    let observed: Error | undefined;
    const app = createApp({
      sql, apiKeys: new Map([["test-client", token]]), onError: (error) => { observed = error; },
    });
    const response = await app.request("/inventory", { headers: postHeaders() });
    expect(response.status).toBe(503);
    expect(response.headers.get("Retry-After")).toBe("1");
    const body = await response.json();
    expect(body.error.code).toBe("database_unavailable");
    expect(JSON.stringify(body)).not.toContain("private-password");
    expect(JSON.stringify(body)).not.toContain("private-endpoint");
    expect(observed).toBe(failure);
  });
});
