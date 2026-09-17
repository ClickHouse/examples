import test from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { rootCertificates } from "node:tls";
import { PrismaPg } from "@prisma/adapter-pg";
import { PrismaClient } from "../src/generated/prisma/client";
import pg from "pg";
import { databaseConfig } from "../src/lib/database-config";
import {
  createRequest,
  editRequest,
  deleteRequest,
  setVote,
  changeStatus,
  listRequests,
} from "../src/lib/board";

// Real managed-service tests. They create only test-prefixed identities and
// remove only their own request IDs. Never point this suite at production data.
test("managed Postgres preserves the board promises", async (t) => {
  const config = databaseConfig();
  const db = new PrismaClient({
    adapter: new PrismaPg(config, { schema: "feature_board" }),
  });
  const prefix = `test_${randomUUID()}`;
  const owner = { userId: `${prefix}_owner`, name: "Test owner" };
  const other = { userId: `${prefix}_other`, name: "Test other" };
  const maintainer = {
    userId: `${prefix}_maintainer`,
    name: "Test maintainer",
  };
  const ids: string[] = [];
  const content = {
    title: "Integration test request",
    description: "This request is temporary test data and will be removed.",
  };
  const oldAllowlist = process.env.MAINTAINER_USER_IDS;
  process.env.MAINTAINER_USER_IDS = maintainer.userId;
  t.after(async () => {
    await db.featureRequest.deleteMany({
      where: { id: { in: ids }, authorId: owner.userId },
    });
    await db.$disconnect();
    if (oldAllowlist === undefined) delete process.env.MAINTAINER_USER_IDS;
    else process.env.MAINTAINER_USER_IDS = oldAllowlist;
  });
  const request = await createRequest(db, owner, content);
  ids.push(request.id);

  await t.test("runtime connection is encrypted", async () => {
    const rows = await db.$queryRaw<
      { ssl: boolean }[]
    >`SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()`;
    assert.equal(rows[0].ssl, true);
  });

  await t.test(
    "24 simultaneous votes by one user produce exactly one vote",
    async () => {
      await Promise.all(
        Array.from({ length: 24 }, () => setVote(db, other, request.id, true)),
      );
      assert.equal(
        await db.vote.count({
          where: { requestId: request.id, userId: other.userId },
        }),
        1,
      );
    },
  );

  await t.test(
    "different users can vote, and repeated unvotes only remove your own vote",
    async () => {
      await setVote(db, owner, request.id, true);
      assert.equal(
        await db.vote.count({ where: { requestId: request.id } }),
        2,
      );
      await Promise.all(
        Array.from({ length: 12 }, () => setVote(db, other, request.id, false)),
      );
      assert.equal(
        await db.vote.count({
          where: { requestId: request.id, userId: other.userId },
        }),
        0,
      );
      assert.equal(
        await db.vote.count({
          where: { requestId: request.id, userId: owner.userId },
        }),
        1,
      );
    },
  );

  await t.test(
    "a new connection observes the vote and a retry keeps it at one",
    async () => {
      const fresh = new PrismaClient({
        adapter: new PrismaPg(config, { schema: "feature_board" }),
      });
      try {
        await setVote(fresh, owner, request.id, true);
        assert.equal(
          await fresh.vote.count({
            where: { requestId: request.id, userId: owner.userId },
          }),
          1,
        );
      } finally {
        await fresh.$disconnect();
      }
    },
  );

  await t.test(
    "another user cannot edit or delete protected records",
    async () => {
      await assert.rejects(
        () =>
          editRequest(db, other, request.id, {
            ...content,
            title: "Unauthorized content",
          }),
        /do not own/,
      );
      await assert.rejects(
        () => deleteRequest(db, other, request.id),
        /do not own/,
      );
      assert.equal(
        (
          await db.featureRequest.findUniqueOrThrow({
            where: { id: request.id },
          })
        ).title,
        content.title,
      );
    },
  );

  await t.test("owner can edit content but cannot choose status", async () => {
    await editRequest(db, owner, request.id, {
      ...content,
      title: "Owner edited this request",
    });
    await assert.rejects(
      () => changeStatus(db, owner, request.id, "SHIPPED"),
      /Only a board maintainer/,
    );
    assert.equal(
      (await db.featureRequest.findUniqueOrThrow({ where: { id: request.id } }))
        .title,
      "Owner edited this request",
    );
  });

  await t.test(
    "maintainer can change status, status filters include the request",
    async () => {
      await changeStatus(db, maintainer, request.id, "PLANNED");
      assert.ok(
        (await listRequests(db, owner.userId, "PLANNED")).some(
          (row) => row.id === request.id,
        ),
      );
      assert.ok(
        !(await listRequests(db, owner.userId, "OPEN")).some(
          (row) => row.id === request.id,
        ),
      );
    },
  );

  await t.test(
    "database constraints reject a duplicate vote and an orphan vote",
    async () => {
      await assert.rejects(
        () =>
          db.vote.create({
            data: { requestId: request.id, userId: owner.userId },
          }),
        { code: "P2002" },
      );
      await assert.rejects(
        () => setVote(db, other, randomUUID(), true),
        /has been deleted/,
      );
    },
  );

  await t.test(
    "the runtime cannot create schema objects, rewrite ownership or touch migrations",
    async () => {
      const client = new pg.Client(config);
      await client.connect();
      try {
        await assert.rejects(
          () =>
            client.query(
              "CREATE TABLE feature_board.forbidden_test (id integer)",
            ),
          { code: "42501" },
        );
        await assert.rejects(
          () => client.query("CREATE TABLE public.forbidden_test (id integer)"),
          { code: "42501" },
        );
        await assert.rejects(
          () =>
            client.query(
              "UPDATE feature_board.feature_requests SET author_id = $1 WHERE id = $2",
              [other.userId, request.id],
            ),
          { code: "42501" },
        );
        await assert.rejects(
          () => client.query("SELECT * FROM feature_board._prisma_migrations"),
          { code: "42501" },
        );
      } finally {
        await client.end();
      }
    },
  );

  await t.test("an unrelated CA fails certificate verification", async () => {
    const client = new pg.Client({
      ...config,
      ssl: { ca: rootCertificates[0], rejectUnauthorized: true },
    });
    try {
      await assert.rejects(
        () => client.connect(),
        /certificate|issuer|self.signed/i,
      );
    } finally {
      await client.end();
    }
  });

  await t.test(
    "owner deletion cascades votes and retries cannot recreate an orphan",
    async () => {
      await deleteRequest(db, owner, request.id);
      assert.equal(
        await db.vote.count({ where: { requestId: request.id } }),
        0,
      );
      await assert.rejects(
        () => setVote(db, other, request.id, true),
        /has been deleted/,
      );
      await setVote(db, other, request.id, false);
    },
  );
});
