import { test } from "node:test";
import assert from "node:assert/strict";
import { linkInput } from "../src/lib/server/input";
const valid = {
  title: " A link ",
  url: "https://example.com/a",
  notes: " Context ",
  tags: "Postgres, postgres, search",
};
test("normalizes and deduplicates tags", () =>
  assert.deepEqual(linkInput(valid), {
    title: "A link",
    url: "https://example.com/a",
    notes: "Context",
    tags: ["postgres", "search"],
  }));
test("rejects unsafe URLs and credentials", () => {
  for (const url of [
    "javascript:alert(1)",
    "file:///etc/passwd",
    "https://user:password@example.com",
    "wrong",
  ])
    assert.throws(() => linkInput({ ...valid, url }));
});
test("bounds title notes and tags", () => {
  for (const bad of [
    { title: "" },
    { title: "a".repeat(201) },
    { notes: "a".repeat(2001) },
    { tags: "invalid tag" },
    { tags: "a,b,c,d,e,f,g,h,i" },
  ])
    assert.throws(() => linkInput({ ...valid, ...bad }));
});
