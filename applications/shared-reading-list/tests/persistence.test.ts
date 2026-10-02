import { test } from "node:test";
import assert from "node:assert/strict";
import { spawn, type ChildProcess } from "node:child_process";
import { once } from "node:events";
import { db, client } from "../src/lib/server/db";
import { user } from "../src/lib/server/schema";
import { eq } from "drizzle-orm";
const base = "http://localhost:3001";
async function start() {
  const child = spawn(process.execPath, ["build"], {
    env: {
      ...process.env,
      HOST: "127.0.0.1",
      SHUTDOWN_TIMEOUT: "1",
      PORT: "3001",
      ORIGIN: base,
      BETTER_AUTH_URL: base,
      SIGNUP_ENABLED: "true",
    },
    stdio: "ignore",
  });
  for (let i = 0; i < 50; i++) {
    try {
      if ((await fetch(base + "/sign-in")).ok) return child;
    } catch {}
    await new Promise((r) => setTimeout(r, 100));
  }
  child.kill();
  throw new Error("Server did not become ready");
}
async function stop(child: ChildProcess) {
  if (child.exitCode === null) {
    child.kill("SIGTERM");
    await once(child, "exit");
  }
}
test("session and saved content survive production process restart", async () => {
  let child: ChildProcess;
  let ownerId: string;
  try {
    child = await start();
    const suffix = crypto.randomUUID();
    const signup = await fetch(base + "/api/auth/sign-up/email", {
      method: "POST",
      headers: { origin: base, "content-type": "application/json" },
      body: JSON.stringify({
        name: "Restart reader",
        email: `restart-${suffix}@example.invalid`,
        password: `Strong-${suffix}`,
      }),
    });
    assert.equal(signup.status, 200);
    ownerId = (await signup.json()).user.id;
    const cookie = signup.headers
      .getSetCookie()
      .map((v) => v.split(";")[0])
      .join("; ");
    const save = await fetch(base + "/?/save", {
      method: "POST",
      redirect: "manual",
      headers: {
        accept: "text/html",
        cookie,
        origin: base,
        "content-type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({
        title: "Persisted reading",
        url: `https://example.com/restart-${suffix}`,
        notes: "Survives a process restart",
        tags: "durable",
      }),
    });
    assert.equal(save.status, 303);
    const location = save.headers.get("location");
    await stop(child);
    child = await start();
    const session = await fetch(base + "/api/auth/get-session", {
      headers: { cookie },
    });
    assert.equal((await session.json()).user.id, ownerId);
    const detail = await fetch(base + location, { headers: { cookie } });
    assert.equal(detail.status, 200);
    assert.ok((await detail.text()).includes("Survives a process restart"));
  } finally {
    if (child!) await stop(child);
    if (ownerId!) await db.delete(user).where(eq(user.id, ownerId));
    await client.end();
  }
});
