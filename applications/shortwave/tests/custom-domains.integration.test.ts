import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { loadEnvFile } from "node:process";
import { test } from "node:test";
import { addDomain, listDomains, removeDomain, verifyDomain as verifyDomainService } from "../src/server/custom-domains";
import { closeDatabases, getPostgres } from "../src/server/db";
import { getAccountId, NotFoundError } from "../src/server/service";

function verifyDomain(user: string, id: string, resolver: { resolveTxt: (name: string) => Promise<string[][]> }) {
  return verifyDomainService(user, id, { createResolver: () => ({ ...resolver, cancel() {} }) });
}

async function allowRecheck(id: string) {
  await getPostgres().query("UPDATE custom_domains SET last_checked_at = now() - interval '1 minute' WHERE id = $1", [id]);
}

// DNS answers are controlled here; the browser journey separately exercises a
// real missing public TXT record. All database fixtures belong to this run.
test("custom-domain claims isolate accounts and require fresh ownership proof", {
  skip: process.env.RUN_INTEGRATION !== "1",
  timeout: 60_000,
}, async (t) => {
  try {
    loadEnvFile(".env");
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
  }
  const runId = randomUUID();
  const owner = `domains_${runId}_a`;
  const outsider = `domains_${runId}_b`;
  const accounts: string[] = [];
  const hostname = (label: string) => `${label}-${runId}.shortwave.dev`;
  try {
    accounts.push(await getAccountId(owner), await getAccountId(outsider));

    await t.test("claims and tokens are private, and tenant checks precede DNS", async () => {
      const domain = await addDomain(owner, hostname("private"));
      assert.equal(domain.status, "pending");
      assert.equal(domain.verifiedAt, null);
      assert.equal(domain.lastCheckedAt, null);
      assert.equal(domain.verificationError, null);
      assert.ok(domain.verificationName.endsWith(`.${domain.hostname}`));
      assert.ok(domain.verificationValue.length >= 43);
      assert.deepEqual(await listDomains(owner), [domain]);
      assert.deepEqual(await listDomains(outsider), []);
      let lookups = 0;
      await assert.rejects(verifyDomain(outsider, domain.id, {
        resolveTxt: async () => { lookups++; return [[domain.verificationValue]]; },
      }), NotFoundError);
      assert.equal(lookups, 0);
      await assert.rejects(removeDomain(outsider, domain.id), NotFoundError);
      assert.deepEqual(await addDomain(owner, domain.hostname.toUpperCase()), domain);
      await closeDatabases();
      assert.deepEqual(await listDomains(owner), [domain]);
      await removeDomain(owner, domain.id);
    });

    await t.test("another account's pending claim cannot reserve a hostname", async () => {
      const first = await addDomain(owner, hostname("shared"));
      const second = await addDomain(outsider, first.hostname);
      assert.notEqual(first.id, second.id);
      assert.notEqual(first.verificationValue, second.verificationValue);
      assert.equal(first.verificationName, second.verificationName);
      const verified = await verifyDomain(outsider, second.id, {
        resolveTxt: async (name: string) => {
          assert.equal(name, `${second.verificationName}.`);
          // TXT character-string chunks form one record; unrelated records do
          // not prevent an exact match elsewhere in the response.
          const value = second.verificationValue;
          return [["unrelated=value"], [value.slice(0, 17), value.slice(17)]];
        },
      });
      assert.equal(verified.status, "verified");
      assert.ok(verified.verifiedAt);
      assert.ok(verified.lastCheckedAt);
      assert.equal(verified.verificationError, null);
      assert.equal((await listDomains(owner))[0]!.status, "pending");
      const conflict = await verifyDomain(owner, first.id, {
        resolveTxt: async () => [[first.verificationValue]],
      });
      assert.equal(conflict.status, "pending");
      assert.ok(conflict.verificationError);
      assert.equal((await listDomains(outsider))[0]!.status, "verified");
      await removeDomain(owner, first.id);
      await removeDomain(outsider, second.id);
    });

    await t.test("only a complete exact token verifies ownership", async () => {
      for (const variant of ["wrong", "substring", "separate-records"]) {
        const domain = await addDomain(owner, hostname(variant));
        const value = domain.verificationValue;
        const records = variant === "wrong" ? [["wrong-value"]]
          : variant === "substring" ? [[`prefix${value}suffix`]]
            : [[value.slice(0, 17)], [value.slice(17)]];
        const checked = await verifyDomain(owner, domain.id, { resolveTxt: async () => records });
        assert.equal(checked.status, "pending", variant);
        assert.equal(checked.verifiedAt, null, variant);
        assert.ok(checked.lastCheckedAt, variant);
        assert.ok(checked.verificationError, variant);
        await removeDomain(owner, domain.id);
      }
    });

    await t.test("missing and failed DNS checks persist actionable pending state", async () => {
      for (const code of ["ENOTFOUND", "ENODATA", "ETIMEOUT", "ESERVFAIL"]) {
        const domain = await addDomain(owner, hostname(code.toLowerCase()));
        const checked = await verifyDomain(owner, domain.id, {
          resolveTxt: async () => { throw Object.assign(new Error("private resolver detail"), { code }); },
        });
        assert.equal(checked.status, "pending", code);
        assert.equal(checked.verifiedAt, null, code);
        assert.ok(checked.lastCheckedAt, code);
        assert.ok(checked.verificationError, code);
        assert.ok(!checked.verificationError!.includes("private resolver detail"));
        assert.deepEqual((await listDomains(owner)).find((item) => item.id === domain.id), checked);
        await removeDomain(owner, domain.id);
      }
    });

    await t.test("cooldown prevents new lookups and rechecks distinguish outages from missing proof", async () => {
      const domain = await addDomain(owner, hostname("recheck"));
      const verified = await verifyDomain(owner, domain.id, { resolveTxt: async () => [[domain.verificationValue]] });
      let lookups = 0;
      await assert.rejects(verifyDomain(owner, domain.id, {
        resolveTxt: async () => { lookups++; return []; },
      }), /10 seconds/);
      assert.equal(lookups, 0);
      await allowRecheck(domain.id);
      const unavailable = await verifyDomain(owner, domain.id, {
        resolveTxt: async () => { throw Object.assign(new Error("timeout"), { code: "ETIMEOUT" }); },
      });
      assert.equal(unavailable.status, "verified");
      assert.equal(unavailable.verifiedAt, verified.verifiedAt);
      assert.ok(unavailable.verificationError);
      await allowRecheck(domain.id);
      const missing = await verifyDomain(owner, domain.id, { resolveTxt: async () => [] });
      assert.equal(missing.status, "pending");
      assert.equal(missing.verifiedAt, null);
      assert.ok(missing.verificationError);
      await removeDomain(owner, domain.id);
    });

    await t.test("simultaneous valid proofs produce only one verified owner", async () => {
      const first = await addDomain(owner, hostname("concurrent"));
      const second = await addDomain(outsider, first.hostname);
      let arrivals = 0;
      let release!: () => void;
      const bothResolving = new Promise<void>((resolve) => { release = resolve; });
      const contenders = [[owner, first], [outsider, second]] as const;
      const results = await Promise.all(contenders.map(async ([user, claim]) => {
        return verifyDomain(user, claim.id, {
          resolveTxt: async () => {
            if (++arrivals === 2) release();
            await bothResolving;
            return [[claim.verificationValue]];
          },
        });
      }));
      assert.equal(results.filter((item) => item.status === "verified").length, 1);
      assert.equal(results.filter((item) => item.status === "pending" && item.verificationError).length, 1);
      const saved = [...await listDomains(owner), ...await listDomains(outsider)];
      assert.equal(saved.filter((item) => item.hostname === first.hostname && item.status === "verified").length, 1);
      await removeDomain(owner, first.id);
      await removeDomain(outsider, second.id);
    });

    await t.test("an older DNS failure cannot overwrite a newer successful check", async () => {
      const domain = await addDomain(owner, hostname("stale-check"));
      let started!: () => void;
      let finish!: (records: string[][]) => void;
      const resolving = new Promise<void>((resolve) => { started = resolve; });
      const answer = new Promise<string[][]>((resolve) => { finish = resolve; });
      const older = verifyDomain(owner, domain.id, { resolveTxt: async () => { started(); return answer; } });
      try {
        await resolving;
        await allowRecheck(domain.id);
        const newer = await verifyDomain(owner, domain.id, { resolveTxt: async () => [[domain.verificationValue]] });
        assert.equal(newer.status, "verified");
        finish([]);
        assert.deepEqual(await older, newer);
        assert.deepEqual((await listDomains(owner)).find((item) => item.id === domain.id), newer);
      } finally {
        finish([]);
        await older;
        await removeDomain(owner, domain.id);
      }
    });

    await t.test("removing and adding a hostname again requires a new token", async () => {
      const original = await addDomain(owner, hostname("readded"));
      await verifyDomain(owner, original.id, { resolveTxt: async () => [[original.verificationValue]] });
      await removeDomain(owner, original.id);
      const replacement = await addDomain(owner, original.hostname);
      assert.notEqual(replacement.id, original.id);
      assert.notEqual(replacement.verificationValue, original.verificationValue);
      assert.equal(replacement.status, "pending");
      assert.equal(replacement.verifiedAt, null);
      const checked = await verifyDomain(owner, replacement.id, { resolveTxt: async () => [[original.verificationValue]] });
      assert.equal(checked.status, "pending");
      await removeDomain(owner, replacement.id);
    });

    await t.test("deletion during DNS cannot recreate a claim or verify its replacement", async () => {
      const original = await addDomain(owner, hostname("deleted-during-check"));
      let started!: () => void;
      let finish!: (records: string[][]) => void;
      const resolving = new Promise<void>((resolve) => { started = resolve; });
      const answer = new Promise<string[][]>((resolve) => { finish = resolve; });
      const check = verifyDomain(owner, original.id, {
        resolveTxt: async () => { started(); return answer; },
      });
      // Attach the rejection assertion before releasing the deferred lookup.
      const rejected = assert.rejects(check, NotFoundError);
      try {
        await resolving;
        await removeDomain(owner, original.id);
        const replacement = await addDomain(owner, original.hostname);
        finish([[original.verificationValue]]);
        await rejected;
        const saved = (await listDomains(owner)).find((item) => item.id === replacement.id)!;
        assert.equal(saved.status, "pending");
        assert.equal(saved.lastCheckedAt, null);
        assert.equal(saved.verificationValue, replacement.verificationValue);
        await removeDomain(owner, replacement.id);
      } finally {
        finish([]);
        await rejected;
      }
    });
  } finally {
    try {
      await getPostgres().query("DELETE FROM custom_domains WHERE account_id = ANY($1::uuid[])", [accounts]);
      await getPostgres().query("DELETE FROM accounts WHERE id = ANY($1::uuid[])", [accounts]);
    } finally {
      await closeDatabases();
    }
  }
});
