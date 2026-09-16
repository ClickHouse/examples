import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { loadEnvFile } from "node:process";
import { test } from "node:test";
import { addDomain, listDomains, removeDomain, verifyDomain } from "../src/server/custom-domains";
import { closeDatabases, getPostgres } from "../src/server/db";
import { createLink, getAccountId, getLink, listLinks, NotFoundError, resolveRedirect, updateLink } from "../src/server/service";

test("domain links preserve URL namespaces and verified tenant ownership", {
  skip: process.env.RUN_INTEGRATION !== "1",
  timeout: 60_000,
}, async (t) => {
  try { loadEnvFile(".env"); }
  catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
  const originalAppUrl = process.env.APP_URL;
  const originalHosted = process.env.PUBLIC_CUSTOM_DOMAINS;
  const run = randomUUID();
  const owner = `domain_links_${run}_a`, outsider = `domain_links_${run}_b`;
  const accounts: string[] = [];
  process.env.APP_URL = "https://dashboard.shortwave.dev";
  try {
    accounts.push(await getAccountId(owner), await getAccountId(outsider));
    const first = await addDomain(owner, `a-${run}.shortwave.dev`);
    const second = await addDomain(outsider, `b-${run}.shortwave.dev`);
    const unhosted = await addDomain(owner, `c-${run}.shortwave.dev`);
    process.env.PUBLIC_CUSTOM_DOMAINS = `${first.hostname}, ${second.hostname}`;
    const input = { slug: `dl-${run}`, destination: "https://example.com/default" };

    await t.test("hosting and ownership are separate prerequisites", async () => {
      assert.equal((await listDomains(owner)).find((d) => d.id === first.id)!.routingReady, false);
      await assert.rejects(createLink(owner, { ...input, domainId: first.id }), /not ready/);
      for (const [user, domain] of [[owner, first], [outsider, second], [owner, unhosted]] as const) {
        const verified = await verifyDomain(user, domain.id, {
          createResolver: () => ({ resolveTxt: async () => [[domain.verificationValue]], cancel() {} }),
        });
        assert.equal(verified.status, "verified");
        assert.equal(verified.routingReady, domain.id !== unhosted.id);
      }
      await assert.rejects(createLink(owner, { ...input, domainId: unhosted.id }), /not ready/);
      await assert.rejects(createLink(outsider, { ...input, domainId: first.id }), NotFoundError);
    });

    const standard = await createLink(owner, input);
    const custom = await createLink(owner, { ...input, domainId: first.id, destination: "https://example.com/custom" });
    const other = await createLink(outsider, { ...input, domainId: second.id, destination: "https://example.com/other" });

    await t.test("same slug works across domains, while each namespace remains unique", async () => {
      assert.equal(standard.domainId, null);
      assert.equal(standard.domainHostname, null);
      assert.equal(custom.domainId, first.id);
      assert.equal(custom.domainHostname, first.hostname);
      assert.deepEqual(await getLink(owner, custom.id), custom);
      assert.equal((await listLinks(owner)).find((l) => l.id === custom.id)!.domainHostname, first.hostname);
      await assert.rejects(createLink(outsider, input), /already in use/);
      await assert.rejects(createLink(owner, { ...input, domainId: first.id }), /already in use/);
      await assert.rejects(getLink(outsider, custom.id), NotFoundError);
      const foreignAssignment = await createLink(outsider, { destination: "https://example.com/foreign-assignment" });
      await assert.rejects(getPostgres().query(
        "UPDATE links SET domain_id = $1 WHERE id = $2", [first.id, foreignAssignment.id],
      ), (error: unknown) => (error as { code?: string }).code === "23503");
    });

    await t.test("trusted request hostname selects exactly one link and unknown hosts fail", async () => {
      assert.deepEqual(await resolveRedirect(input.slug, {}, false), { status: 302, location: standard.resolvedUrl });
      assert.deepEqual(await resolveRedirect(input.slug, {}, false, "dashboard.shortwave.dev"), { status: 302, location: standard.resolvedUrl });
      assert.deepEqual(await resolveRedirect(input.slug, {}, false, first.hostname), { status: 302, location: custom.resolvedUrl });
      assert.deepEqual(await resolveRedirect(input.slug, {}, false, second.hostname), { status: 302, location: other.resolvedUrl });
      assert.deepEqual(await resolveRedirect(input.slug, {}, false, "unknown.shortwave.dev"), { status: 404 });
      const defaultOnly = await createLink(owner, { destination: "https://example.com/default-only" });
      assert.deepEqual(await resolveRedirect(defaultOnly.slug, {}, false, first.hostname), { status: 404 });
    });

    await t.test("redirect events belong to the selected link and HEAD does not add events", async () => {
      await resolveRedirect(input.slug, {}, true, first.hostname);
      await resolveRedirect(input.slug, {}, false, second.hostname);
      const events = await getPostgres().query("SELECT event FROM click_outbox WHERE account_id = ANY($1::uuid[])", [accounts]);
      assert.equal(events.rows.length, 1);
      assert.equal(events.rows[0].event.link_id, custom.id);
      assert.equal(events.rows[0].event.account_id, accounts[0]);
    });

    await t.test("domain is immutable and failed reassignment rolls back other edits", async () => {
      await assert.rejects(updateLink(owner, custom.id, { destination: "https://example.com/changed", domainId: null }), /cannot be changed/);
      assert.deepEqual(await getLink(owner, custom.id), custom);
      await assert.rejects(updateLink(owner, standard.id, { ...input, domainId: first.id }), /cannot be changed/);
      const edited = await updateLink(owner, custom.id, { destination: "https://example.com/edited" });
      assert.equal(edited.domainId, first.id);
      assert.equal(edited.domainHostname, first.hostname);
      assert.equal(edited.slug, custom.slug);
    });

    await t.test("domains with live or disabled links cannot be removed", async () => {
      await assert.rejects(removeDomain(outsider, first.id), NotFoundError);
      await assert.rejects(removeDomain(owner, first.id), /has links/);
      await updateLink(owner, custom.id, { destination: custom.destination, domainId: first.id, enabled: false });
      assert.deepEqual(await resolveRedirect(input.slug, {}, false, first.hostname), { status: 410 });
      await assert.rejects(removeDomain(owner, first.id), /has links/);
      await updateLink(owner, custom.id, { destination: custom.destination, enabled: true });
    });

    await t.test("hosting removal and missing ownership proof stop routing immediately", async () => {
      process.env.PUBLIC_CUSTOM_DOMAINS = second.hostname;
      assert.deepEqual(await resolveRedirect(input.slug, {}, false, first.hostname), { status: 404 });
      assert.equal((await listDomains(owner)).find((d) => d.id === first.id)!.routingReady, false);
      process.env.PUBLIC_CUSTOM_DOMAINS = `${first.hostname},${second.hostname}`;
      await getPostgres().query("UPDATE custom_domains SET last_checked_at = now() - interval '1 minute' WHERE id = $1", [first.id]);
      const revoked = await verifyDomain(owner, first.id, { createResolver: () => ({ resolveTxt: async () => [], cancel() {} }) });
      assert.equal(revoked.status, "pending");
      assert.equal(revoked.routingReady, false);
      assert.deepEqual(await resolveRedirect(input.slug, {}, false, first.hostname), { status: 404 });
      assert.deepEqual(await resolveRedirect(input.slug, {}, false), { status: 302, location: standard.resolvedUrl });
      await assert.rejects(removeDomain(owner, first.id), /has links/);
    });
    await t.test("a newly verified owner cannot inherit a previous owner's links", async () => {
      const replacement = await addDomain(outsider, first.hostname);
      await verifyDomain(outsider, replacement.id, {
        createResolver: () => ({ resolveTxt: async () => [[replacement.verificationValue]], cancel() {} }),
      });
      assert.deepEqual(await resolveRedirect(input.slug, {}, false, first.hostname), { status: 404 });
      const replacementLink = await createLink(outsider, { ...input, domainId: replacement.id, destination: "https://example.com/new-owner" });
      assert.deepEqual(await resolveRedirect(input.slug, {}, false, first.hostname), { status: 302, location: replacementLink.resolvedUrl });
      assert.equal((await getLink(owner, custom.id)).domainId, first.id);
    });
  } finally {
    if (originalAppUrl === undefined) Reflect.deleteProperty(process.env, "APP_URL"); else process.env.APP_URL = originalAppUrl;
    if (originalHosted === undefined) Reflect.deleteProperty(process.env, "PUBLIC_CUSTOM_DOMAINS"); else process.env.PUBLIC_CUSTOM_DOMAINS = originalHosted;
    try {
      await getPostgres().query("DELETE FROM click_outbox WHERE account_id = ANY($1::uuid[])", [accounts]);
      await getPostgres().query("DELETE FROM links WHERE account_id = ANY($1::uuid[])", [accounts]);
      await getPostgres().query("DELETE FROM account_tags WHERE account_id = ANY($1::uuid[])", [accounts]);
      await getPostgres().query("DELETE FROM custom_domains WHERE account_id = ANY($1::uuid[])", [accounts]);
      await getPostgres().query("DELETE FROM accounts WHERE id = ANY($1::uuid[])", [accounts]);
    } finally { await closeDatabases(); }
  }
});
