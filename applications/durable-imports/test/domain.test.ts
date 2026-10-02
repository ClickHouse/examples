import test from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { normalize, ApiError } from "../src/input.js";
const input = () => ({
  requestId: randomUUID(),
  rows: [
    { email: " SYNTHETIC@EXAMPLE.TEST ", name: "  Ｃａｓｅｙ\t  Example " },
  ],
});
test("normalization and request retry fingerprint are deterministic", () => {
  const value = normalize(input());
  assert.deepEqual(value.rows, [
    { email: "synthetic@example.test", name: "Casey Example" },
  ]);
  const replay = normalize({
    requestId: value.requestId.toUpperCase(),
    rows: value.rows,
  });
  assert.equal(value.fingerprint, replay.fingerprint);
  assert.equal(value.requestId, replay.requestId);
});
test("malformed/extra fields, duplicate emails and invalid Unicode are rejected", () => {
  for (const value of [
    null,
    [],
    { ...input(), accountId: randomUUID() },
    { ...input(), rows: [{ email: "x@example.test", name: "\ud800" }] },
    { ...input(), rows: [{ email: "x@example.test", name: "hidden\0" }] },
    {
      ...input(),
      rows: [
        { email: "x@example.test", name: "One" },
        { email: "X@example.test", name: "Two" },
      ],
    },
  ])
    assert.throws(() => normalize(value), ApiError);
});
test("row, byte and PostgreSQL codepoint bounds are independent", () => {
  assert.throws(
    () =>
      normalize({
        ...input(),
        rows: Array.from({ length: 101 }, (_, n) => ({
          email: `x${n}@example.test`,
          name: "A",
        })),
      }),
    ApiError,
  );
  assert.throws(
    () =>
      normalize({
        ...input(),
        rows: [{ email: "x@example.test", name: "x".repeat(70_000) }],
      }),
    (e: unknown) => e instanceof ApiError && e.status === 413,
  );
  assert.equal(
    normalize({
      ...input(),
      rows: [{ email: "x@example.test", name: "😀".repeat(80) }],
    }).rows[0]!.name.length,
    160,
  );
  assert.throws(
    () =>
      normalize({
        ...input(),
        rows: [{ email: "x@example.test", name: "😀".repeat(81) }],
      }),
    ApiError,
  );
});
