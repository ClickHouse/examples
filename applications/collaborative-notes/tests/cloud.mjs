import assert from "node:assert/strict";
import { checkServerIdentity } from "node:tls";
import pg from "pg";
import * as Y from "yjs";
import { databaseConfig, createPool } from "../dist-server/server/database.js";
import { PostgresStorage } from "../dist-server/server/store.js";
const runtime = createPool();
const owner = createPool({
  ...process.env,
  PGUSER: process.env.OWNER_USER,
  PGPASSWORD: process.env.OWNER_PASSWORD,
});
const storage = new PostgresStorage(runtime);
let cases = 0;
async function control(name, fn) {
  await fn();
  cases++;
  console.log(`PASS ${name}`);
}
async function row() {
  return (
    await owner.query(
      "SELECT state,revision,stored_at FROM notes.documents WHERE id='meeting-notes'",
    )
  ).rows[0];
}
try {
  await control(
    "actual binary inserts/deletes, reordered/repeated snapshots",
    async () => {
      const base = await storage.load("meeting-notes");
      const doc = new Y.Doc({ gc: false });
      Y.applyUpdate(doc, base);
      const initial = doc.getText("content").toString();
      doc.getText("content").insert(initial.length, " ABC");
      const older = Y.encodeStateAsUpdate(doc);
      doc.getText("content").delete(initial.length + 2, 1);
      const newer = Y.encodeStateAsUpdate(doc);
      await storage.store("meeting-notes", newer);
      await storage.store("meeting-notes", older);
      await storage.store("meeting-notes", newer);
      const loaded = new Y.Doc({ gc: false });
      Y.applyUpdate(loaded, await storage.load("meeting-notes"));
      assert.equal(loaded.getText("content").toString(), initial + " AC");
      doc.destroy();
      loaded.destroy();
    },
  );
  await control(
    "independent row-lock contention merges both snapshots",
    async () => {
      const base = await storage.load("meeting-notes");
      const a = new Y.Doc({ gc: false });
      const b = new Y.Doc({ gc: false });
      Y.applyUpdate(a, base);
      Y.applyUpdate(b, base);
      a.getText("content").insert(0, "left ");
      b.getText("content").insert(0, "right ");
      const blocker = await owner.connect();
      await blocker.query("BEGIN");
      await blocker.query(
        "SELECT id FROM notes.documents WHERE id='meeting-notes' FOR UPDATE",
      );
      let completed = 0;
      const operations = [
        storage.store("meeting-notes", Y.encodeStateAsUpdate(a)),
        storage.store("meeting-notes", Y.encodeStateAsUpdate(b)),
      ].map((p) => p.then(() => completed++));
      await new Promise((r) => setTimeout(r, 400));
      assert.equal(completed, 0);
      await blocker.query("COMMIT");
      blocker.release();
      await Promise.all(operations);
      const merged = new Y.Doc();
      Y.applyUpdate(merged, await storage.load("meeting-notes"));
      const value = merged.getText("content").toString();
      assert(value.includes("left "));
      assert(value.includes("right "));
      a.destroy();
      b.destroy();
      merged.destroy();
    },
  );
  await control(
    "actual deferred commit failure rolls back binary and revision",
    async () => {
      const before = await row();
      await owner.query(
        "CREATE FUNCTION notes.fail_commit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'fixture commit failure'; END $$",
      );
      await owner.query(
        "CREATE CONSTRAINT TRIGGER fixture_failure AFTER UPDATE ON notes.documents DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION notes.fail_commit()",
      );
      try {
        const doc = new Y.Doc();
        Y.applyUpdate(doc, before.state);
        doc.getText("content").insert(0, "rollback ");
        await assert.rejects(
          storage.store("meeting-notes", Y.encodeStateAsUpdate(doc)),
          /fixture commit failure/,
        );
        doc.destroy();
        const after = await row();
        assert.deepEqual(after, before);
      } finally {
        await owner.query("DROP TRIGGER fixture_failure ON notes.documents");
        await owner.query("DROP FUNCTION notes.fail_commit()");
      }
    },
  );
  await control(
    "runtime role rejects DDL, TEMP, insertion, deletion and metadata edits",
    async () => {
      for (const sql of [
        "CREATE TABLE notes.forbidden(id int)",
        "CREATE TEMP TABLE forbidden(id int)",
        "INSERT INTO notes.documents(id,title,state) VALUES('x','x',decode('0000','hex'))",
        "DELETE FROM notes.documents WHERE id='meeting-notes'",
        "UPDATE notes.documents SET title='changed' WHERE id='meeting-notes'",
      ]) {
        await assert.rejects(runtime.query(sql), (e) => e.code === "42501");
      }
    },
  );
  await control(
    "verified CA positive and certificate/name-specific negatives through actual factory",
    async () => {
      await runtime.query("SELECT 1");
      const caConfig = databaseConfig();
      caConfig.ssl = { ...caConfig.ssl, ca: "" };
      const wrongCA = new pg.Pool(caConfig);
      try {
        await assert.rejects(wrongCA.query("SELECT 1"), (e) =>
          [
            "UNABLE_TO_VERIFY_LEAF_SIGNATURE",
            "SELF_SIGNED_CERT_IN_CHAIN",
            "UNABLE_TO_GET_ISSUER_CERT_LOCALLY",
          ].includes(e.code),
        );
      } finally {
        await wrongCA.end();
      }
      const nameConfig = databaseConfig();
      nameConfig.ssl = {
        ...nameConfig.ssl,
        checkServerIdentity: (_host, cert) =>
          checkServerIdentity("wrong-host.invalid", cert),
      };
      const wrongName = new pg.Pool(nameConfig);
      try {
        await assert.rejects(
          wrongName.query("SELECT 1"),
          (e) => e.code === "ERR_TLS_CERT_ALTNAME_INVALID",
        );
      } finally {
        await wrongName.end();
      }
      console.log(
        "Hostname negative invokes Node checkServerIdentity with substituted wrong-host.invalid; production factory has no custom verifier.",
      );
    },
  );
  await control(
    "fixed allowlist and binary bounds rejected before writing",
    async () => {
      await assert.rejects(storage.load("foreign-note"), /Unknown note/);
      await assert.rejects(
        storage.store("meeting-notes", new Uint8Array(524289)),
        /limit/i,
      );
    },
  );
  console.log(`${cases} distinct Cloud storage/role/TLS controls passed.`);
} finally {
  await runtime.end();
  await owner.end();
}
