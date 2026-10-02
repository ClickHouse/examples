import assert from "node:assert/strict";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { openSync, closeSync } from "node:fs";
import { spawn } from "node:child_process";
const base = process.env.BASE_URL || "http://127.0.0.1:3000";
const origin = new URL(base).origin;
const output = process.env.EVIDENCE_DIR || "/tmp/team-directory-evidence";
const pidFile = process.env.SERVER_PID_FILE;
assert.ok(pidFile, "Set SERVER_PID_FILE to the production server PID file.");
await mkdir(output, { recursive: true });
const login = await fetch(base + "/api/auth/login", {
  method: "POST",
  headers: { Origin: origin, "Content-Type": "application/json" },
  body: JSON.stringify({
    email: "alex@example.test",
    password: process.env.DEMO_PASSWORD,
  }),
});
assert.equal(login.status, 200);
const cookie = login.headers
  .getSetCookie()
  .find((c) => c.startsWith("nuxt-session="))
  .split(";")[0];
async function snapshot() {
  const response = await fetch(
    base + "/api/profiles/00000000-0000-4000-8000-000000000001",
    { headers: { Cookie: cookie } },
  );
  assert.equal(response.status, 200);
  return response.json();
}
const before = await snapshot();
const oldPid = Number((await readFile(pidFile, "utf8")).trim());
process.kill(oldPid, "SIGTERM");
let exited = false;
for (let i = 0; i < 100; i++) {
  try {
    const stat = await readFile(`/proc/${oldPid}/stat`, "utf8");
    if (stat.split(" ")[2] === "Z") {
      exited = true;
      break;
    }
  } catch (error) {
    if (error.code === "ENOENT") {
      exited = true;
      break;
    }
    throw error;
  }
  await new Promise((resolve) => setTimeout(resolve, 100));
}
assert.ok(exited, "Original server must exit before its replacement starts.");
await assert.rejects(() =>
  fetch(base + "/login", { signal: AbortSignal.timeout(2000) }),
);
const keys = [
  "PGHOST",
  "PGPORT",
  "PGDATABASE",
  "PGUSER",
  "PGPASSWORD",
  "PGSSLROOTCERT",
  "NUXT_SESSION_PASSWORD",
  "NUXT_APP_ORIGIN",
  "NUXT_SESSION_SECURE",
  "NUXT_SESSION_COOKIE_SECURE",
  "NITRO_HOST",
  "NITRO_PORT",
  "NODE_ENV",
  "PATH",
  "HOME",
];
const env = Object.fromEntries(
  keys
    .filter((k) => process.env[k] !== undefined)
    .map((k) => [k, process.env[k]]),
);
assert.ok(
  !Object.keys(env).some((k) => k.startsWith("TEST_") || k === "DEMO_PASSWORD"),
);
const log = openSync(output + "/restarted-server.log", "a", 0o600);
const replacement = spawn(process.execPath, [".output/server/index.mjs"], {
  cwd: process.cwd(),
  env,
  detached: true,
  stdio: ["ignore", log, log],
});
replacement.unref();
closeSync(log);
await writeFile(pidFile, String(replacement.pid) + "\n", { mode: 0o600 });
assert.notEqual(replacement.pid, oldPid);
let ready = false;
for (let i = 0; i < 100; i++) {
  try {
    if (
      (await fetch(base + "/login", { signal: AbortSignal.timeout(2000) })).ok
    ) {
      ready = true;
      break;
    }
  } catch {}
  await new Promise((resolve) => setTimeout(resolve, 100));
}
assert.ok(ready, "Replacement server must become ready.");
assert.deepEqual(await snapshot(), before);
const session = await fetch(base + "/api/_auth/session", {
  headers: { Cookie: cookie },
});
assert.equal(session.status, 200);
assert.equal((await session.json()).user.id, before.id);
console.log(
  `Real production restart ${oldPid} → ${replacement.pid}; original exited and listener absent before start; same sealed cookie and complete profile/skills/revision survived.`,
);
console.log(
  "Replacement received only runtime database credentials, cookie secret, origin/cookie configuration and standard process variables.",
);
