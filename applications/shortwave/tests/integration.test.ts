import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { loadEnvFile } from "node:process";
import { test } from "node:test";
import { defaultQrStyle } from "../src/lib/domain";
import type { ClickEvent } from "../src/lib/types";
import { getAnalytics } from "../src/server/analytics";
import { closeDatabases, getClickHouse, getPostgres } from "../src/server/db";
import { flushOutbox } from "../src/server/outbox";
import {
  createLink,
  createFolder,
  listFolders,
  updateFolder,
  deleteFolder,
  createTemplate,
  deleteTemplate,
  getAccountId,
  getLink,
  listLinks,
  listTags,
  listTemplates,
  NotFoundError,
  resolveRedirect,
  saveQrStyle,
  updateLink,
  updateTemplate,
} from "../src/server/service";

// Uses configured databases and unique synthetic accounts. Never run alongside
// the global outbox worker. Only these accounts' Postgres records are removed;
// their ClickHouse events expire under the event table's normal TTL.
test(
  "real Postgres and ClickHouse: ownership, redirects, durable retries and deduplication",
  {
    skip: process.env.RUN_INTEGRATION !== "1",
    timeout: 120_000,
  },
  async (t) => {
    try {
      loadEnvFile(".env");
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
    }
    const runId = randomUUID();
    const owner = `integration_${runId}_a`;
    const outsider = `integration_${runId}_b`;
    const accountIds: string[] = [];
    const originalDatabase = process.env.CLICKHOUSE_DATABASE;
    try {
      const account = await getAccountId(owner);
      accountIds.push(account);
      const otherAccount = await getAccountId(outsider);
      accountIds.push(otherAccount);
      assert.equal(await getAccountId(owner), account);
      const slug = `it-${runId}`;
      const link = await createLink(owner, {
        slug,
        destination: "https://example.com/first?keep=1#anchor",
        title: "Integration A",
        tags: ["integration"],
        utm: { campaign: "before" },
      });
      const otherLink = await createLink(outsider, {
        slug: `ib-${runId}`,
        destination: "https://example.org/other",
        title: "Integration B",
      });

      await t.test(
        "link, QR and template operations enforce account ownership",
        async () => {
          assert.deepEqual(
            (await listLinks(owner)).map((row) => row.id),
            [link.id],
          );
          assert.deepEqual(
            (await listLinks(outsider)).map((row) => row.id),
            [otherLink.id],
          );
          assert.deepEqual(await listLinks(outsider, { search: slug }), []);
          assert.equal(
            (await listLinks(owner, { tag: "integration" })).length,
            1,
          );
          await assert.rejects(getLink(outsider, link.id), NotFoundError);
          await assert.rejects(
            updateLink(outsider, link.id, {
              destination: "https://example.org/stolen",
            }),
            NotFoundError,
          );
          await assert.rejects(
            saveQrStyle(outsider, link.id, defaultQrStyle),
            NotFoundError,
          );
          const style = { ...defaultQrStyle, dots: "rounded" as const };
          assert.deepEqual(await saveQrStyle(owner, link.id, style), style);
          assert.deepEqual((await getLink(owner, link.id)).qrStyle, style);
          assert.equal(
            (await getLink(outsider, otherLink.id)).qrStyle.dots,
            "square",
          );
          await assert.rejects(
            createLink(outsider, {
              slug,
              destination: "https://example.org/duplicate",
            }),
            /already in use/,
          );

          const template = await createTemplate(owner, {
            name: "Integration campaign",
            values: { campaign: "copied" },
          });
          assert.deepEqual(await listTemplates(outsider), []);
          await assert.rejects(
            updateTemplate(outsider, template.id, {
              name: "Stolen",
              values: {},
            }),
            NotFoundError,
          );
          await assert.rejects(
            deleteTemplate(outsider, template.id),
            NotFoundError,
          );
          const copied = await createLink(owner, {
            destination: "https://example.com/template",
            utm: template.values,
          });
          await updateTemplate(owner, template.id, {
            name: "Renamed",
            values: { campaign: "changed" },
          });
          assert.equal(
            (await getLink(owner, copied.id)).utm.campaign,
            "copied",
          );
          assert.equal((await listTemplates(owner))[0]?.name, "Renamed");
          await deleteTemplate(owner, template.id);
          assert.deepEqual(await listTemplates(owner), []);
        },
      );

      await t.test(
        "saved tags persist across link edits and connections, with account-scoped literal matching",
        async () => {
          const tagged = await createLink(owner, {
            destination: "https://example.com/tags",
            tags: ["Launch", "news_100%", "Launch"],
          });
          assert.deepEqual(tagged.tags, ["Launch", "news_100%"]);
          assert.deepEqual(await listTags(owner, "laun"), ["Launch"]);
          assert.deepEqual(await listTags(owner, "%"), ["news_100%"]);
          assert.deepEqual(await listTags(outsider, "Launch"), []);
          await updateLink(owner, tagged.id, {
            destination: tagged.destination,
            tags: ["Edited"],
          });
          await closeDatabases();
          assert.deepEqual(await listTags(owner, "Launch"), ["Launch"]);
          assert.deepEqual(await listTags(owner, "edited"), ["Edited"]);
          const reused = await createLink(owner, {
            destination: "https://example.com/reused",
            tags: ["Launch"],
          });
          assert.deepEqual(reused.tags, ["Launch"]);
          await assert.rejects(updateLink(outsider, tagged.id, {
            destination: tagged.destination,
            tags: ["unauthorized-tag"],
          }), NotFoundError);
          assert.deepEqual(await listTags(outsider, "unauthorized-tag"), []);
          await assert.rejects(createLink(owner, {
            slug: tagged.slug,
            destination: tagged.destination,
            tags: ["failed-save-tag"],
          }), /already in use/);
          assert.deepEqual(await listTags(owner, "failed-save-tag"), []);
          await createLink(outsider, {
            destination: "https://example.org/private-tags",
            tags: ["outsider-only"],
          });
          assert.deepEqual(await listTags(owner, "outsider-only"), []);
        },
      );

      await t.test("folders isolate accounts, assign atomically, and delete without deleting links", async () => {
        const folder = await createFolder(owner, "Launch");
        const privateFolder = await createFolder(outsider, "Private");
        assert.deepEqual(await listFolders(owner), [folder]);
        assert.deepEqual(await listFolders(outsider), [privateFolder]);
        await assert.rejects(createFolder(owner, "launch"), /folder name is already/);
        await assert.rejects(updateFolder(outsider, folder.id, "Stolen"), NotFoundError);
        await assert.rejects(deleteFolder(outsider, folder.id), NotFoundError);
        const filed = await createLink(owner, {
          destination: "https://example.com/filed", tags: ["folder-test"], folderId: folder.id,
        });
        assert.equal(filed.folderId, folder.id);
        assert.deepEqual((await listLinks(owner, { folderId: folder.id })).map((item) => item.id), [filed.id]);
        assert.deepEqual(await listLinks(outsider, { folderId: folder.id }), []);
        assert.ok(!(await listLinks(owner, { folderId: null })).some((item) => item.id === filed.id));
        await assert.rejects(createLink(owner, {
          destination: "https://example.com/invalid-folder", folderId: privateFolder.id, tags: ["invalid-folder-save"],
        }), NotFoundError);
        assert.deepEqual(await listTags(owner, "invalid-folder-save"), []);
        assert.deepEqual(await listLinks(owner, { search: "invalid-folder" }), []);
        await assert.rejects(updateLink(owner, filed.id, {
          destination: "https://example.com/unauthorized-edit", folderId: privateFolder.id,
        }), NotFoundError);
        assert.equal((await getLink(owner, filed.id)).destination, filed.destination);
        assert.equal((await getLink(owner, filed.id)).folderId, folder.id);
        await assert.rejects(updateLink(outsider, filed.id, {
          destination: filed.destination, folderId: privateFolder.id,
        }), NotFoundError);
        // Composite foreign keys also reject a cross-account membership directly.
        await assert.rejects(getPostgres().query(
          "UPDATE link_folders SET folder_id = $1 WHERE link_id = $2", [privateFolder.id, filed.id],
        ), (error: unknown) => (error as { code?: string }).code === "23503");
        await updateLink(owner, filed.id, { destination: filed.destination, tags: filed.tags });
        assert.equal((await getLink(owner, filed.id)).folderId, folder.id);
        const renamed = await updateFolder(owner, folder.id, "Release");
        assert.equal(renamed.name, "Release");
        assert.equal((await getLink(owner, filed.id)).folderId, folder.id);
        const unfiled = await updateLink(owner, filed.id, { destination: filed.destination, tags: filed.tags, folderId: null });
        assert.equal(unfiled.folderId, null);
        await updateLink(owner, filed.id, { destination: filed.destination, tags: filed.tags, folderId: folder.id });
        await deleteFolder(owner, folder.id);
        assert.deepEqual(await listFolders(owner), []);
        const retained = await getLink(owner, filed.id);
        assert.equal(retained.folderId, null);
        assert.deepEqual(retained.tags, ["folder-test"]);
        assert.ok((await listLinks(owner, { folderId: null })).some((item) => item.id === filed.id));
      });

      await t.test(
        "redirects immediately observe edits and disabled state; HEAD does not count",
        async () => {
          assert.deepEqual(
            await resolveRedirect(slug, {
              referrer: "https://news.example.org/private?token=private",
              userAgent: "Firefox/130.0",
            }),
            { status: 302, location: link.resolvedUrl },
          );
          const edited = await updateLink(owner, link.id, {
            slug: "ignored-new-slug",
            destination: "https://example.com/edited",
            utm: { campaign: "after" },
            tags: ["integration"],
          });
          assert.equal(edited.slug, slug);
          assert.deepEqual(await resolveRedirect(slug), {
            status: 302,
            location: edited.resolvedUrl,
          });
          assert.deepEqual(await resolveRedirect(slug, {}, false), {
            status: 302,
            location: edited.resolvedUrl,
          });
          await updateLink(owner, link.id, {
            destination: edited.destination,
            enabled: false,
          });
          assert.deepEqual(await resolveRedirect(slug), { status: 410 });
          assert.deepEqual(await resolveRedirect(`missing-${runId}`), {
            status: 404,
          });
          assert.deepEqual(await resolveRedirect("../invalid"), {
            status: 404,
          });
          const rows = await getPostgres().query(
            "SELECT event FROM click_outbox WHERE account_id = $1 ORDER BY created_at",
            [account],
          );
          assert.equal(rows.rows.length, 2);
          assert.equal(rows.rows[0].event.utm_campaign, "before");
          assert.equal(rows.rows[1].event.utm_campaign, "after");
          assert.equal(rows.rows[0].event.referrer_domain, "news.example.org");
          assert.equal(JSON.stringify(rows.rows).includes("private"), false);
          await resolveRedirect(otherLink.slug);
        },
      );

      await t.test(
        "failed delivery survives client restart and retries without losing events",
        async () => {
          const queued = await getPostgres().query(
            "SELECT event FROM click_outbox WHERE account_id = $1",
            [account],
          );
          assert.equal(queued.rows.length, 2);
          const snapshot = queued.rows.map((row) => row.event as ClickEvent);
          const initial = await getAnalytics(owner);
          assert.equal(initial.status, "delayed");
          assert.equal(initial.pendingEvents, 2);
          await closeDatabases();
          process.env.CLICKHOUSE_DATABASE = `missing_integration_${runId.replaceAll("-", "")}`;
          assert.deepEqual(await flushOutbox(500, account), {
            delivered: 0,
            failed: 2,
          });
          const failed = await getPostgres().query(
            "SELECT attempts, next_attempt_at > now() AS deferred FROM click_outbox WHERE account_id = $1",
            [account],
          );
          assert.equal(failed.rows.length, 2);
          assert.ok(
            failed.rows.every((row) => row.attempts === 1 && row.deferred),
          );
          await closeDatabases();
          if (originalDatabase === undefined)
            Reflect.deleteProperty(process.env, "CLICKHOUSE_DATABASE");
          else process.env.CLICKHOUSE_DATABASE = originalDatabase;
          const persisted = await getPostgres().query(
            "SELECT event FROM click_outbox WHERE account_id = $1 ORDER BY event_id",
            [account],
          );
          assert.deepEqual(
            persisted.rows
              .map((row) => row.event)
              .sort((a, b) => a.event_id.localeCompare(b.event_id)),
            snapshot.sort((a, b) => a.event_id.localeCompare(b.event_id)),
          );
          // Make only this test account's backoff due; no arbitrary wall-clock sleep.
          await getPostgres().query(
            "UPDATE click_outbox SET next_attempt_at = now() - interval '1 second' WHERE account_id = $1",
            [account],
          );
          assert.deepEqual(await flushOutbox(500, account), {
            delivered: 2,
            failed: 0,
          });
          assert.deepEqual(await flushOutbox(500, otherAccount), {
            delivered: 1,
            failed: 0,
          });
          assert.deepEqual(await flushOutbox(500, account), {
            delivered: 0,
            failed: 0,
          });
          // Simulate an insert acknowledged by ClickHouse but lost before the queue
          // commit. A durable copy is delivered again with the same immutable ID.
          const repeated = snapshot[0]!;
          await getPostgres().query(
            "INSERT INTO click_outbox (event_id, account_id, event) VALUES ($1,$2,$3)",
            [repeated.event_id, account, JSON.stringify(repeated)],
          );
          assert.deepEqual(await flushOutbox(500, account), {
            delivered: 1,
            failed: 0,
          });
          const counts = await getClickHouse().query({
            query:
              "SELECT count() AS physical, uniqExact(event_id) AS distinct_events FROM click_events WHERE account_id = {account:UUID}",
            query_params: { account },
            format: "JSONEachRow",
          });
          const [count] = await counts.json<{
            physical: string;
            distinct_events: string;
          }>();
          assert.equal(Number(count?.physical), 3);
          assert.equal(Number(count?.distinct_events), 2);
        },
      );

      await t.test(
        "analytics count immutable event IDs and isolate accounts and filters",
        async () => {
          const analytics = await getAnalytics(owner, { days: 7 });
          assert.equal(analytics.status, "ready");
          assert.equal(analytics.totalClicks, 2);
          assert.equal(analytics.pendingEvents, 0);
          assert.equal(analytics.daily.length, 7);
          assert.equal(
            analytics.daily.reduce((sum, row) => sum + row.clicks, 0),
            2,
          );
          assert.deepEqual(
            analytics.topLinks.map((row) => row.linkId),
            [link.id],
          );
          assert.equal(
            analytics.campaigns.find((row) => row.name === "before")?.clicks,
            1,
          );
          assert.equal(
            analytics.campaigns.find((row) => row.name === "after")?.clicks,
            1,
          );
          assert.equal(
            (await getAnalytics(owner, { campaign: "before" })).totalClicks,
            1,
          );
          assert.equal(
            (await getAnalytics(owner, { linkId: link.id })).totalClicks,
            2,
          );
          const other = await getAnalytics(outsider);
          assert.equal(other.status, "ready");
          assert.equal(other.totalClicks, 1);
          assert.deepEqual(
            other.topLinks.map((row) => row.linkId),
            [otherLink.id],
          );
          await assert.rejects(
            getAnalytics(outsider, { linkId: link.id }),
            NotFoundError,
          );
        },
      );
    } finally {
      await closeDatabases();
      if (originalDatabase === undefined)
        Reflect.deleteProperty(process.env, "CLICKHOUSE_DATABASE");
      else process.env.CLICKHOUSE_DATABASE = originalDatabase;
      try {
        for (const table of [
          "click_outbox",
          "utm_templates",
          "links",
          "accounts",
        ]) {
          const column = table === "accounts" ? "id" : "account_id";
          await getPostgres().query(
            `DELETE FROM ${table} WHERE ${column} = ANY($1::uuid[])`,
            [accountIds],
          );
        }
      } finally {
        await closeDatabases();
      }
    }
  },
);
