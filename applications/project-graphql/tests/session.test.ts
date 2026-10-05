import { test } from "node:test";
import assert from "node:assert/strict";
import {
  passwordHash,
  passwordMatches,
  cookieToken,
} from "../src/server/sessions.ts";
import { validateOperation } from "../src/server/limits.ts";
test("stored password verifier refuses mismatches and cookies reject ambiguous tokens", () => {
  const hash = passwordHash("correct", "salt");
  assert.equal(passwordMatches("wrong", "salt", hash), false);
  assert.equal(passwordMatches("correct", "salt", hash), true);
  assert.equal(
    cookieToken(
      "ground_session=" + "a".repeat(64) + "; ground_session=" + "b".repeat(64),
    ),
    null,
  );
  assert.equal(cookieToken("ground_session=forged"), null);
});
test("real GraphQL AST bounds expanded fragments and connection variables", () => {
  validateOperation(
    "query Q($n:Int!){allProjects(first:$n){nodes{id}}}",
    { n: 20 },
    "Q",
  );
  for (const n of [0, 51, null])
    assert.throws(() =>
      validateOperation(
        "query Q($n:Int!){allProjects(first:$n){nodes{id}}}",
        { n },
        "Q",
      ),
    );
  assert.throws(() => validateOperation("{__schema{queryType{name}}}", {}));
  assert.throws(() =>
    validateOperation("query{a{...X}} fragment X on X{b{...X}}", {}),
  );
  assert.throws(() => validateOperation("{allProjects{nodes{id}}}", {}));
});

test("pagination checks expand named and inline fragments at connection level", () => {
  assert.throws(() =>
    validateOperation(
      "query{allProjects{...Rows}} fragment Rows on ProjectsConnection {nodes{id}}",
      {},
    ),
  );
  assert.throws(() =>
    validateOperation(
      "{allProjects{... on ProjectsConnection {nodes{id}}}}",
      {},
    ),
  );
  validateOperation(
    "query{allProjects(first:20){...Rows}} fragment Rows on ProjectsConnection {nodes{id}}",
    {},
  );
});
