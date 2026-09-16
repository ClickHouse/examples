import assert from "node:assert/strict";
import test from "node:test";
import diagnostic from "../scripts/workers-connectivity-check";

test("diagnostic refuses absent, incorrect and unset bearer tokens before accessing databases", async () => {
  for (const [token, authorization] of [["fixture-secret", ""], ["fixture-secret", "Bearer incorrect"], ["", "Bearer "]] as const) {
    const env = { DIAGNOSTIC_TOKEN: token } as Env & { DIAGNOSTIC_TOKEN: string };
    const response = await diagnostic.fetch(new Request("https://example.com/", { headers: { authorization } }), env);
    assert.equal(response.status, 401);
    assert.equal(await response.text(), "Unauthorized");
    assert.equal(response.headers.get("Cache-Control"), "no-store");
  }
});

test("diagnostic refuses non-GET methods and arbitrary port overrides", async () => {
  const env = { DIAGNOSTIC_TOKEN: "fixture-secret" } as Env & { DIAGNOSTIC_TOKEN: string };
  const headers = { authorization: "Bearer fixture-secret" };
  const method = await diagnostic.fetch(new Request("https://example.com/", { method: "POST", headers }), env);
  assert.equal(method.status, 401);
  const port = await diagnostic.fetch(new Request("https://example.com/?port=22", { headers }), env);
  assert.equal(port.status, 400);
});
