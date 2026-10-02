import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { spawn, execFileSync, type ChildProcess } from "node:child_process";
import { once } from "node:events";
import { setTimeout as delay } from "node:timers/promises";
import { after, afterEach, before, test } from "node:test";
import pg from "pg";
import { checkServerIdentity, type ConnectionOptions } from "node:tls";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { databaseConfig } from "../src/database.js";
import { Imports } from "../src/imports.js";
import { CASEY, MORGAN, ApiError } from "../src/input.js";
import { QUEUE, queue } from "../src/queue.js";

process.env.NODE_ENV = "test";
const config = databaseConfig();
const owner = new pg.Pool({
  ...config,
  user: "imports_migration",
  password: process.env.MIGRATION_PASSWORD,
});
const api = new pg.Pool({
  ...config,
  user: "imports_api",
  password: process.env.APP_PASSWORD,
});
const workerDb = new pg.Pool({
  ...config,
  user: "imports_worker",
  password: process.env.WORKER_PASSWORD,
});
const producer = queue();
const imports = new Imports(api, producer);
const children = new Set<ChildProcess>();
const casey = CASEY;
const morgan = MORGAN;
const input = (requestId = randomUUID()) => ({
  requestId,
  rows: [
    { email: " Casey@Example.test ", name: " Casey   Example " },
    { email: "morgan@example.test", name: "Morgan Example" },
  ],
});

async function eventually<T>(
  read: () => Promise<T>,
  acceptable: (value: T) => boolean,
  timeout = 60_000,
): Promise<T> {
  const deadline = Date.now() + timeout;
  let last: T;
  do {
    last = await read();
    if (acceptable(last)) return last;
    await delay(200);
  } while (Date.now() < deadline);
  throw new Error(
    `Timed out waiting for expected state: ${JSON.stringify(last)}`,
  );
}
function launch(
  script: "server" | "worker",
  fault: Record<string, string> = {},
) {
  const env: NodeJS.ProcessEnv = {};
  // Child processes receive only their runtime password, never owner/admin credentials.
  for (const key of [
    "PATH",
    "HOME",
    "PGHOST",
    "PGPORT",
    "PGDATABASE",
    "PGSSLROOTCERT",
  ])
    env[key] = process.env[key];
  Object.assign(env, {
    NODE_ENV: "test",
    PGUSER: script === "server" ? "imports_api" : "imports_worker",
    PGPASSWORD:
      script === "server"
        ? process.env.APP_PASSWORD
        : process.env.WORKER_PASSWORD,
    PORT: "4081",
    ...fault,
  });
  if (script === "server")
    Object.assign(env, {
      CASEY_TOKEN: process.env.CASEY_TOKEN,
      MORGAN_TOKEN: process.env.MORGAN_TOKEN,
    });
  const child = spawn(process.execPath, [`dist/src/${script}.js`], {
    env,
    stdio: ["ignore", "pipe", "pipe", "ipc"],
  });
  let output = "";
  child.stdout!.on("data", (data) => {
    output += data.toString();
  });
  child.stderr!.on("data", (data) => {
    output += data.toString();
  });
  children.add(child);
  child.once("exit", () => children.delete(child));
  return { child, output: () => output };
}
async function readyWorker(fault: Record<string, string> = {}) {
  const proc = launch("worker", fault);
  await eventually(
    async () => ({
      alive: proc.child.exitCode === null,
      output: proc.output(),
    }),
    (s) => s.output.includes("Import worker ready"),
    20_000,
  );
  return proc;
}
async function stop(child: ChildProcess, signal: NodeJS.Signals = "SIGTERM") {
  if (child.exitCode !== null || child.signalCode !== null) return;
  const exited = once(child, "exit");
  child.kill(signal);
  await Promise.race([
    exited,
    delay(30_000).then(() => {
      throw new Error("Process did not stop");
    }),
  ]);
  assert(child.exitCode !== null || child.signalCode !== null);
}
async function counts(id: string) {
  const {
    rows: [row],
  } = await owner.query(
    `SELECT i.state, i.result_count, j.state::text AS job_state, j.retry_count,
    (SELECT count(*)::integer FROM contact_imports.contacts c WHERE c.import_id=i.id) AS effects
    FROM contact_imports.imports i LEFT JOIN import_jobs.job j ON j.id=i.id WHERE i.id=$1`,
    [id],
  );
  return row;
}
async function settled(id: string, state = "succeeded") {
  return eventually(
    () => counts(id),
    (r) =>
      r.state === state &&
      (state !== "succeeded" || r.job_state === "completed"),
  );
}
async function request(
  path: string,
  token = process.env.CASEY_TOKEN!,
  body?: unknown,
) {
  return fetch(`http://127.0.0.1:4081${path}`, {
    method: body === undefined ? "GET" : "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
}
before(async () => {
  await producer.start();
});
afterEach(async () => {
  for (const child of [...children]) await stop(child);
});
after(async () => {
  for (const child of [...children]) await stop(child);
  await producer.stop();
  await Promise.all([owner.end(), api.end(), workerDb.end()]);
});

test(
  "verified TLS, same-endpoint controls and restricted runtime roles",
  { timeout: 40_000 },
  async () => {
    assert.equal(
      (await api.query("SELECT current_user AS role")).rows[0].role,
      "imports_api",
    );
    const goodSsl = config.ssl as ConnectionOptions;
    const certDir = mkdtempSync(join(tmpdir(), "imports-wrong-ca-"));
    execFileSync(
      "openssl",
      [
        "req",
        "-x509",
        "-newkey",
        "rsa:2048",
        "-nodes",
        "-keyout",
        join(certDir, "key.pem"),
        "-out",
        join(certDir, "ca.pem"),
        "-days",
        "1",
        "-subj",
        "/CN=unrelated-test-ca",
      ],
      { stdio: "ignore" },
    );
    const wrongCa = readFileSync(join(certDir, "ca.pem"), "utf8");
    rmSync(certDir, { recursive: true });
    for (const [ssl, expected] of [
      [
        { ...goodSsl, ca: wrongCa },
        /SELF_SIGNED_CERT_IN_CHAIN|UNABLE_TO_VERIFY_LEAF_SIGNATURE|UNABLE_TO_GET_ISSUER_CERT_LOCALLY/,
      ],
      [
        {
          ...goodSsl,
          checkServerIdentity: (
            _host: string,
            certificate: Parameters<typeof checkServerIdentity>[1],
          ) => checkServerIdentity("wrong-hostname.example.test", certificate),
        },
        /ERR_TLS_CERT_ALTNAME_INVALID/,
      ],
    ] as const) {
      const bad = new pg.Client({ ...config, ssl });
      try {
        await assert.rejects(
          bad.connect(),
          (error: NodeJS.ErrnoException) => (
            console.log("Negative TLS control", error.code),
            expected.test(error.code ?? "")
          ),
        );
      } finally {
        await bad.end();
      }
    }
    assert.equal(
      (await api.query("SELECT 1 AS positive_control")).rows[0]
        .positive_control,
      1,
    );
    for (const db of [api, workerDb]) {
      await assert.rejects(
        db.query(
          "SELECT import_jobs.create_queue('runtime-forbidden', '{}'::jsonb)",
        ),
        (e: pg.DatabaseError) => e.code === "42501",
      );
      for (const sql of [
        "CREATE TABLE contact_imports.runtime_ddl(id int)",
        "UPDATE import_jobs.version SET version=version",
        "UPDATE contact_imports.imports SET payload='[]'::jsonb WHERE false",
      ]) {
        await assert.rejects(
          db.query(sql),
          (error: pg.DatabaseError) => error.code === "42501",
        );
      }
    }
    await assert.rejects(
      api.query("UPDATE import_jobs.job SET state='active' WHERE false"),
      (e: pg.DatabaseError) => e.code === "42501",
    );
    await assert.rejects(
      workerDb.query(
        "UPDATE contact_imports.contacts SET name='changed' WHERE false",
      ),
      (e: pg.DatabaseError) => e.code === "42501",
    );
    console.log(
      "TLS trust and hostname failures verified; positive same-endpoint connection and role denials passed",
    );
  },
);

test(
  "enqueue rollback, competing retries and account-scoped request retention",
  { timeout: 40_000 },
  async () => {
    const submission = input();
    const beforeCount = (
      await owner.query(
        "SELECT submission_count FROM contact_imports.accounts WHERE id=$1",
        [casey],
      )
    ).rows[0].submission_count;
    await assert.rejects(
      imports.submit(casey, submission, async () => {
        throw new Error("After both writes");
      }),
      /After both writes/,
    );
    assert.equal(
      (
        await owner.query(
          "SELECT count(*)::integer AS n FROM contact_imports.imports WHERE request_id=$1",
          [submission.requestId],
        )
      ).rows[0].n,
      0,
    );
    assert.equal(
      (await owner.query("SELECT count(*)::integer AS n FROM import_jobs.job"))
        .rows[0].n,
      0,
    );
    assert.equal(
      (
        await owner.query(
          "SELECT submission_count FROM contact_imports.accounts WHERE id=$1",
          [casey],
        )
      ).rows[0].submission_count,
      beforeCount,
    );
    const repeated = await Promise.all(
      Array.from({ length: 8 }, () => imports.submit(casey, submission)),
    );
    assert.equal(new Set(repeated.map((r) => r.id)).size, 1);
    assert.equal(repeated.filter((r) => !r.replay).length, 1);
    assert.equal(
      (
        await owner.query(
          "SELECT count(*)::integer AS n FROM import_jobs.job WHERE id=$1",
          [repeated[0]!.id],
        )
      ).rows[0].n,
      1,
    );
    await assert.rejects(
      imports.submit(casey, {
        ...submission,
        rows: [...submission.rows].reverse(),
      }),
      (e: ApiError) => e.status === 409,
    );
    await assert.rejects(
      imports.status(morgan, repeated[0]!.id),
      (e: ApiError) => e.status === 404,
    );
    const first = await readyWorker();
    const second = await readyWorker();
    const outcome = await settled(repeated[0]!.id);
    assert.equal(outcome.effects, 2);
    assert.equal(outcome.result_count, 2);
    // A separate import may contain the same email; contacts are import-scoped results.
    const other = await imports.submit(casey, input());
    await settled(other.id);
    assert.equal((await imports.results(casey, other.id)).length, 2);
    const replayJob = randomUUID();
    await producer.send(
      QUEUE,
      { importId: repeated[0]!.id },
      { id: replayJob },
    );
    await eventually(
      async () =>
        (
          await owner.query(
            "SELECT state::text AS state FROM import_jobs.job WHERE id=$1",
            [replayJob],
          )
        ).rows[0]?.state,
      (state) => state === "completed",
    );
    assert.equal((await counts(repeated[0]!.id)).effects, 2);
    await stop(first.child);
    await stop(second.child);
    console.log(
      "Eight concurrent repeats produced one import/job; two worker processes and completion replay produced no duplicate effects",
    );
  },
);

test("bounded account submission limits are coordinated by database locks", async () => {
  const pending = [];
  for (let i = 0; i < 5; i++)
    pending.push(await imports.submit(morgan, input()));
  await assert.rejects(
    imports.submit(morgan, input()),
    (e: ApiError) => e.status === 429,
  );
  assert.equal(
    (
      await imports.submit(
        morgan,
        input(
          (
            await owner.query(
              "SELECT request_id FROM contact_imports.imports WHERE id=$1",
              [pending[0]!.id],
            )
          ).rows[0].request_id,
        ),
      )
    ).replay,
    true,
  );
  const worker = await readyWorker();
  for (const p of pending) await settled(p.id);
  await stop(worker.child);
  await owner.query(
    "UPDATE contact_imports.accounts SET submission_count=50 WHERE id=$1",
    [morgan],
  );
  await assert.rejects(
    imports.submit(morgan, input()),
    (e: ApiError) => e.status === 429,
  );
  await owner.query(
    "UPDATE contact_imports.accounts SET window_start=clock_timestamp()-interval '25 hours' WHERE id=$1",
    [morgan],
  );
  await imports.submit(morgan, input());
  assert.equal(
    (
      await owner.query(
        "SELECT submission_count FROM contact_imports.accounts WHERE id=$1",
        [morgan],
      )
    ).rows[0].submission_count,
    1,
  );
});

test(
  "handler failure rolls effects and completion back, then retries successfully",
  { timeout: 60_000 },
  async () => {
    const submitted = await imports.submit(casey, input());
    const worker = await readyWorker({
      TEST_IMPORT_ID: submitted.id,
      TEST_FAIL_ATTEMPTS: "1",
    });
    await eventually(
      () => counts(submitted.id),
      (r) => r.job_state === "retry",
    );
    const rolledBack = await counts(submitted.id);
    assert.equal(rolledBack.state, "queued");
    assert.equal(rolledBack.effects, 0);
    assert.equal(rolledBack.result_count, null);
    const final = await settled(submitted.id);
    assert.equal(final.retry_count, 1);
    assert.equal(final.effects, 2);
    assert(!worker.output().includes("Queue operation error"), worker.output());
    await stop(worker.child);
    console.log(
      "Fault after contacts and result update left zero effects/no completion; retry committed both",
    );
  },
);

test(
  "three failed attempts become durable failure; runtime retention preserves reported outcome",
  { timeout: 100_000 },
  async () => {
    const submitted = await imports.submit(casey, input());
    const worker = await readyWorker({
      TEST_IMPORT_ID: submitted.id,
      TEST_FAIL_ATTEMPTS: "3",
    });
    await eventually(
      () => imports.status(casey, submitted.id),
      (r) => r.state === "failed",
    );
    const final = await counts(submitted.id);
    assert.equal(final.retry_count, 2);
    assert.equal(final.job_state, "failed");
    assert.equal(final.effects, 0);
    await owner.query(
      "UPDATE import_jobs.job SET completed_on=clock_timestamp()-interval '2 days', keep_until=clock_timestamp()-interval '2 days' WHERE id=$1",
      [submitted.id],
    );
    // Rewind only the test queue's maintenance cadence. A runtime-only supervisor performs DELETE.
    await owner.query(
      "UPDATE import_jobs.queue SET maintain_on=clock_timestamp()-interval '2 minutes' WHERE name=$1",
      [QUEUE],
    );
    await eventually(
      async () =>
        (
          await owner.query(
            "SELECT count(*)::integer AS n FROM import_jobs.job WHERE id=$1",
            [submitted.id],
          )
        ).rows[0].n,
      (n) => n === 0,
      75_000,
    );
    assert.equal(
      (await imports.status(casey, submitted.id)).error,
      "Queue retry limit exhausted",
    );
    assert(!worker.output().includes("Queue operation error"), worker.output());
    await stop(worker.child);
    console.log(
      "Retry limit exhausted after three attempts; runtime retention deleted queue metadata, durable failure remained",
    );
  },
);

test(
  "real SIGKILL after uncommitted effects recovers through runtime expiry without duplicates",
  { timeout: 100_000 },
  async () => {
    const submitted = await imports.submit(casey, input());
    const doomed = launch("worker", {
      TEST_IMPORT_ID: submitted.id,
      TEST_PAUSE_AFTER_EFFECTS: "true",
    });
    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(
        () => reject(new Error("No effects-written kill point")),
        25_000,
      );
      doomed.child.on("message", (message: any) => {
        if (
          message.type === "effects_written" &&
          message.importId === submitted.id
        ) {
          clearTimeout(timeout);
          resolve();
        }
      });
    });
    assert.equal((await counts(submitted.id)).effects, 0);
    assert.equal((await counts(submitted.id)).state, "queued");
    assert.equal((await counts(submitted.id)).job_state, "active");
    await stop(doomed.child, "SIGKILL");
    const survivor = await readyWorker();
    const recovered = await settled(submitted.id);
    assert(recovered.retry_count >= 1);
    assert.equal(recovered.effects, 2);
    assert.equal(recovered.result_count, 2);
    assert(
      !survivor.output().includes("Queue operation error"),
      survivor.output(),
    );
    await stop(survivor.child);
    console.log(
      "SIGKILL confirmed exited; active claim recovered via supervisor, effects and completion committed once",
    );
  },
);

test(
  "HTTP account isolation, malformed requests and real API/worker restart",
  { timeout: 60_000 },
  async () => {
    const server = launch("server");
    await eventually(
      async () => {
        try {
          return (await fetch("http://127.0.0.1:4081/health")).status;
        } catch {
          return 0;
        }
      },
      (status) => status === 200,
      20_000,
    );
    assert.equal(
      (await request("/imports", "wrong-token", input())).status,
      401,
    );
    assert.equal(
      (
        await request("/imports", process.env.CASEY_TOKEN!, {
          ...input(),
          accountId: morgan,
        })
      ).status,
      400,
    );
    assert.equal(
      (
        await request("/imports", process.env.CASEY_TOKEN!, {
          ...input(),
          rows: [{ email: "x@example.test", name: "bad\u0000name" }],
        })
      ).status,
      400,
    );
    assert.equal(
      (
        await request("/imports", process.env.CASEY_TOKEN!, {
          requestId: randomUUID(),
          rows: "x".repeat(70_000),
        })
      ).status,
      413,
    );
    const submittedResponse = await request(
      "/imports",
      process.env.CASEY_TOKEN!,
      input(),
    );
    assert.equal(submittedResponse.status, 202);
    const submitted = (await submittedResponse.json()) as { id: string };
    assert.equal(
      (await request(`/imports/${submitted.id}`, process.env.MORGAN_TOKEN!))
        .status,
      404,
    );
    assert.equal(
      (
        await request(
          `/imports/${submitted.id}/results`,
          process.env.MORGAN_TOKEN!,
        )
      ).status,
      404,
    );
    assert.equal(
      (await request(`/imports/${submitted.id}/results`)).status,
      409,
    );
    await stop(server.child);
    const worker = await readyWorker();
    await settled(submitted.id);
    await stop(worker.child);
    const newWorker = await readyWorker();
    const restarted = launch("server");
    await eventually(
      async () => {
        try {
          return (await fetch("http://127.0.0.1:4081/health")).status;
        } catch {
          return 0;
        }
      },
      (status) => status === 200,
      20_000,
    );
    const result = await request(`/imports/${submitted.id}/results`);
    assert.equal(result.status, 200);
    assert.equal(((await result.json()) as { rows: unknown[] }).rows.length, 2);
    await stop(restarted.child);
    await stop(newWorker.child);
    console.log(
      "Native HTTP acceptance and confirmed API/worker process restarts retained the durable result",
    );
  },
);

test("lost queue metadata is explicit rather than eternal processing", async () => {
  const submitted = await imports.submit(casey, input());
  await owner.query("DELETE FROM import_jobs.job WHERE id=$1", [submitted.id]);
  const result = await imports.status(casey, submitted.id);
  assert.equal(result.state, "failed");
  assert.equal(result.error, "Queue metadata no longer available");
});
