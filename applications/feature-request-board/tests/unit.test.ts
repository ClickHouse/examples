import test from "node:test";
import assert from "node:assert/strict";
import type { PrismaClient } from "../src/generated/prisma/client";
import {
  parseContent,
  parseStatus,
  parseRequestId,
  isMaintainer,
  decodeCursor,
  encodeCursor,
  BoardError,
} from "../src/lib/validation";
import { databaseConfig } from "../src/lib/database-config";
import {
  createRequest,
  editRequest,
  deleteRequest,
  setVote,
  changeStatus,
} from "../src/lib/board";

const id = "10000000-0000-4000-8000-000000000001";
const content = {
  title: "A useful feature",
  description: "A useful explanation of the problem.",
};

test("content is trimmed and bounded on the server", () => {
  assert.deepEqual(
    parseContent({
      title: `  ${content.title}  `,
      description: `  ${content.description}  `,
    }),
    content,
  );
  for (const input of [
    { ...content, title: "tiny" },
    { ...content, title: "a".repeat(121) },
    { ...content, description: "tiny" },
    { ...content, description: "a".repeat(4001) },
    { ...content, title: null },
    { ...content, description: new Blob() },
  ])
    assert.throws(() => parseContent(input), BoardError);
});

test("text bounds count Unicode code points like PostgreSQL char_length", () => {
  assert.throws(
    () => parseContent({ ...content, title: "🌱".repeat(4) }),
    /8–120/,
  );
  assert.equal(
    parseContent({ ...content, title: "🌱".repeat(8) }).title,
    "🌱".repeat(8),
  );
  assert.throws(
    () => parseContent({ ...content, description: "🌱".repeat(10) }),
    /20–4,000/,
  );
});

test("status and IDs accept only the expected values", () => {
  assert.equal(parseStatus("IN_PROGRESS"), "IN_PROGRESS");
  assert.equal(parseRequestId(id), id);
  assert.throws(() => parseStatus("unknown"), BoardError);
  assert.throws(() => parseStatus(["OPEN"]), BoardError);
  assert.throws(() => parseRequestId("not-a-uuid"), BoardError);
});

test("maintainer allowlist matches whole Clerk IDs and defaults to nobody", () => {
  assert.equal(isMaintainer("user_a", " user_a, user_b "), true);
  assert.equal(isMaintainer("user_a", "user_ab"), false);
  assert.equal(isMaintainer(null, "user_a"), false);
  assert.equal(isMaintainer("user_a", ""), false);
});

test("page cursors round-trip and invalid values fail closed", () => {
  const cursor = { id, createdAt: new Date("2026-09-17T12:00:00.000Z") };
  assert.deepEqual(decodeCursor(encodeCursor(cursor)), cursor);
  assert.equal(decodeCursor(undefined), undefined);
  assert.throws(() => decodeCursor("bad cursor"), BoardError);
  assert.throws(() => decodeCursor("a".repeat(121)), BoardError);
});

test("runtime refuses TLS URL overrides and missing CA configuration", () => {
  const base = {
    DATABASE_URL: "postgresql://user:password@db.example.com/postgres",
    DATABASE_CA_PATH: "does-not-exist.pem",
  };
  assert.throws(() => databaseConfig({}), /Set DATABASE_URL/);
  for (const query of [
    "sslmode=disable",
    "sslmode=require",
    "sslrootcert=bad.pem",
    "schema=feature_board",
  ]) {
    assert.throws(
      () =>
        databaseConfig({
          ...base,
          DATABASE_URL: `${base.DATABASE_URL}?${query}`,
        }),
      /without query parameters/,
    );
  }
  assert.throws(() => databaseConfig(base), /ENOENT/);
});

test("all mutations require an authenticated actor before touching the database", async () => {
  const db = {} as PrismaClient;
  for (const operation of [
    () => createRequest(db, null, content),
    () => editRequest(db, null, id, content),
    () => deleteRequest(db, null, id),
    () => setVote(db, null, id, true),
    () => changeStatus(db, null, id, "SHIPPED"),
  ])
    await assert.rejects(operation, /Sign in/);
});

test("being an author does not confer status privileges", async () => {
  const previous = process.env.MAINTAINER_USER_IDS;
  process.env.MAINTAINER_USER_IDS = "user_maintainer";
  try {
    await assert.rejects(
      () =>
        changeStatus(
          {} as PrismaClient,
          { userId: "user_author", name: "Author" },
          id,
          "SHIPPED",
        ),
      /Only a board maintainer/,
    );
  } finally {
    if (previous === undefined) delete process.env.MAINTAINER_USER_IDS;
    else process.env.MAINTAINER_USER_IDS = previous;
  }
});
