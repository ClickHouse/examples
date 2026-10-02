import test from "node:test";
import assert from "node:assert/strict";
import {
  profileInput,
  directoryInput,
  literalLike,
} from "../server/domain/validation.mjs";
const valid = {
  revision: 1,
  displayName: " Alex ",
  biography: "Builds tools",
  location: "London",
  skillIds: [3, 1],
};
test("normalizes a complete profile without changing the expected revision", () => {
  assert.deepEqual(profileInput(valid), {
    ...valid,
    displayName: "Alex",
    skillIds: [1, 3],
  });
});
test("rejects owner injection, duplicate skills, excessive choices and invalid revisions", () => {
  for (const patch of [
    { ownerId: "someone" },
    { skillIds: [1, 1] },
    { skillIds: [1, 2, 3, 4, 5, 6, 7] },
    { skillIds: ["1"] },
    { revision: 0 },
    { revision: 1.1 },
  ])
    assert.throws(() => profileInput({ ...valid, ...patch }));
});
test("rejects non-string fields, empty names, excess text and Unicode controls", () => {
  for (const patch of [
    { displayName: [] },
    { displayName: " " },
    { biography: "x".repeat(1001) },
    { location: "a\u007fb" },
    { biography: "a\u0085b" },
  ])
    assert.throws(() => profileInput({ ...valid, ...patch }));
});
test("bounds paging and allowlists ordering", () => {
  assert.equal(directoryInput({}).page, 1);
  for (const query of [
    { page: "1001" },
    { page: "0" },
    { sort: "email; DROP TABLE users" },
    { skill: "-1" },
    { q: "x".repeat(81) },
    { q: ["Alex", "Sam"] },
  ])
    assert.throws(() => directoryInput(query));
});
test("search punctuation stays literal rather than becoming SQL wildcards", () => {
  assert.equal(literalLike("50%_\\"), "50\\%\\_\\\\");
});
