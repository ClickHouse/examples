import assert from "node:assert/strict";
import { spawn, execFile } from "node:child_process";
import { once } from "node:events";
import { mkdir } from "node:fs/promises";
import { createServer } from "node:http";
import { promisify } from "node:util";
import { chromium } from "playwright";
import WebSocket from "ws";

const execute = promisify(execFile);
const appDir = process.env.APP_DIR;
const evidence = process.env.EVIDENCE_DIR;
assert.ok(appDir && evidence);
await mkdir(evidence, { recursive: true });
const port = 4083;
const origin = `http://127.0.0.1:${port}`;
const env = Object.fromEntries(
  ["HOME", "PATH", "PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD", "PGSSLROOTCERT"]
    .map((key) => [key, process.env[key]]),
);
env.LANG = "C.UTF-8";
env.PORT = String(port);
env.APP_ORIGIN = origin;
const rscript = process.env.RSCRIPT || "/home/al/R/bin/Rscript";
let processHandle;
let browser;
let external;
let checks = 0;
const pass = (message) => console.log(`PASS ${++checks}: ${message}`);
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
async function start() {
  const child = spawn(rscript, ["run.R"], { cwd: appDir, env, stdio: ["ignore", "pipe", "pipe"] });
  child.stdout.on("data", (data) => process.stdout.write(data));
  child.stderr.on("data", (data) => process.stderr.write(data));
  processHandle = child;
  for (let attempt = 0; attempt < 150; attempt++) {
    if (child.exitCode !== null) throw new Error("Shiny exited during startup");
    try {
      const response = await fetch(origin);
      if (response.ok) return child.pid;
    } catch { /* Wait for the actual listener. */ }
    await sleep(100);
  }
  throw new Error("Shiny startup timed out");
}
async function stop() {
  const child = processHandle;
  if (!child || child.exitCode !== null) return;
  const exited = once(child, "exit");
  child.kill("SIGINT");
  let forced = false;
  const timeout = setTimeout(() => { forced = true; child.kill("SIGKILL"); }, 10000);
  const [code, signal] = await exited;
  clearTimeout(timeout);
  assert.equal(forced, false, "Shiny must actually exit after interrupt");
  assert.equal(code, 0, `Unexpected shutdown ${signal}`);
  processHandle = undefined;
}
async function connected(page) {
  await page.goto(origin);
  await page.waitForFunction(() => window.Shiny?.shinyapp?.isConnected());
  await page.locator("#poll_id option").first().waitFor({ state: "attached" });
}
async function waitText(page, selector, text) {
  await page.waitForFunction(({ selector, text }) =>
    document.querySelector(selector)?.textContent.includes(text), { selector, text });
}
async function createPoll(page, question, choices) {
  await page.locator("#question").fill(question);
  await page.locator("#choice_lines").fill(choices.join("\n"));
  await page.locator("#create").click();
  await waitText(page, "#summary_heading", question);
  return page.locator("#poll_id").inputValue();
}
async function storedQuestionCount(question) {
  const { stdout } = await execute(rscript, ["test/observe.R", question], { cwd: appDir, env });
  return JSON.parse(stdout);
}
function missingOriginAttempt(question) {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(`ws://127.0.0.1:${port}/websocket`);
    const timeout = setTimeout(() => { socket.terminate(); reject(new Error("Missing Origin did not close")); }, 5000);
    socket.on("error", reject);
    socket.on("open", () => socket.send(JSON.stringify({ method: "init", data: {
      question, choice_lines: "One\nTwo", "create:shiny.action": 1,
    } })));
    socket.on("close", () => { clearTimeout(timeout); resolve(); });
  });
}

try {
  const firstPid = await start();
  browser = await chromium.launch({ headless: true });
  const contextA = await browser.newContext({ viewport: { width: 1440, height: 1100 } });
  const contextB = await browser.newContext({ viewport: { width: 1440, height: 1100 } });
  const pageA = await contextA.newPage();
  const pageB = await contextB.newPage();
  const errors = [];
  pageA.on("pageerror", (error) => errors.push(error.message));
  pageB.on("pageerror", (error) => errors.push(error.message));
  await connected(pageA);
  const questionA = `Browser workshop ${Date.now()}`;
  const idA = await createPoll(pageA, questionA, ["Paper planets", "Tiny gardens", "Quiet circuits"]);
  assert.match(idA, /^[1-9][0-9]*$/);
  await pageA.locator("#code").fill("sample_b01");
  await pageA.locator("#respond").click();
  await waitText(pageA, "#summary_heading", "1 saved responses");
  await waitText(pageA, "#last_result", "Response saved once.");
  await pageA.waitForFunction(() => document.querySelector("#counts img")?.naturalWidth > 0);
  await pageA.screenshot({ path: `${evidence}/desktop.png`, fullPage: true });
  pass("real browser creates choices, saves one response and renders stored chart/counts");

  await connected(pageB);
  await pageB.locator("#poll_id").selectOption(idA);
  await waitText(pageB, "#summary_heading", questionA);
  await pageA.locator("#respond").click();
  await waitText(pageA, "#last_result", "Matching saved response replayed.");
  await pageA.getByLabel("Tiny gardens", { exact: true }).check();
  await pageA.locator("#respond").click();
  await pageA.getByText("This code already selected a different choice.", { exact: true }).waitFor();
  await pageB.locator("#refresh").click();
  await waitText(pageB, "#summary_heading", "1 saved responses");
  pass("matching code replays, changed choice conflicts and another context refreshes committed counts");

  await pageB.locator("#close").click();
  await waitText(pageB, "#poll_state", "Closed");
  await pageA.locator("#refresh").click();
  await waitText(pageA, "#poll_state", "Closed");
  await pageA.getByLabel("Paper planets", { exact: true }).check();
  await pageA.locator("#respond").click();
  await waitText(pageA, "#last_result", "Matching saved response replayed.");
  await pageA.locator("#code").fill("new_after_close");
  await pageA.locator("#respond").click();
  await pageA.getByText("Poll is closed; matching saved responses can still replay.", { exact: true }).waitFor();
  await waitText(pageA, "#summary_heading", "1 saved responses");
  pass("close coordinates stored state and preserves matching replay while denying a new response");

  const questionB = `Second browser poll ${Date.now()}`;
  const idB = await createPoll(pageA, questionB, ["Garden <img src=x onerror=alert(1)>", "Paper"]);
  assert.notEqual(idB, idA);
  await waitText(pageA, "#poll_state", "Open");
  assert.equal(await pageA.locator("#choice_id img").count(), 0);
  await pageA.locator("#code").fill("sample_second");
  await pageA.locator("#respond").click();
  await waitText(pageA, "#summary_heading", "1 saved responses");
  pass("second creation selects the new poll and labels remain escaped");

  const questionC = `Eight choices ${Date.now()}`;
  const longLabels = Array.from({ length: 8 }, (_, index) =>
    `Option ${index + 1} ${"abcdefghijkl".repeat(7)}`.slice(0, 80));
  await createPoll(pageA, questionC, longLabels);
  await pageA.locator("#code").fill("sample_long");
  await pageA.locator("#respond").click();
  await waitText(pageA, "#summary_heading", "1 saved responses");
  await pageA.setViewportSize({ width: 390, height: 844 });
  await waitText(pageA, "#count_table", longLabels[7]);
  await pageA.waitForFunction(() => {
    const image = document.querySelector("#counts img");
    return image && Math.abs(image.naturalWidth - document.querySelector("#counts").clientWidth) < 5;
  });
  await pageA.waitForFunction(() => document.querySelector("#counts img")?.naturalWidth > 0);
  await pageA.screenshot({ path: `${evidence}/mobile.png`, fullPage: true });
  assert.ok(await pageA.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
  pass("eight maximum-length labels retain full table text and a bounded mobile chart/layout");

  external = createServer((_request, response) => { response.end("<!doctype html><title>Origin fixture</title>"); });
  await new Promise((resolve) => external.listen(4084, "127.0.0.1", resolve));
  const outsider = await contextB.newPage();
  await outsider.goto("http://127.0.0.1:4084");
  const foreignQuestion = `FOREIGN_ORIGIN_${Date.now()}`;
  const closed = await outsider.evaluate(({ port, question }) => new Promise((resolve, reject) => {
    const socket = new WebSocket(`ws://127.0.0.1:${port}/websocket`);
    const timeout = setTimeout(() => { socket.close(); reject(new Error("Foreign Origin remained open")); }, 5000);
    socket.onopen = () => socket.send(JSON.stringify({ method: "init", data: {
      question, choice_lines: "One\nTwo", "create:shiny.action": 1,
    } }));
    socket.onclose = () => { clearTimeout(timeout); resolve(true); };
    socket.onerror = () => { clearTimeout(timeout); reject(new Error("WebSocket transport failed")); };
  }), { port, question: foreignQuestion });
  assert.equal(closed, true);
  const missingQuestion = `MISSING_ORIGIN_${Date.now()}`;
  await missingOriginAttempt(missingQuestion);
  assert.equal(await storedQuestionCount(foreignQuestion), 0);
  assert.equal(await storedQuestionCount(missingQuestion), 0);
  assert.equal(await storedQuestionCount(questionA), 1);
  pass("actual foreign-browser and missing-Origin WebSockets close without a write; real-browser control exists");

  await stop();
  const secondPid = await start();
  assert.notEqual(secondPid, firstPid);
  await connected(pageA);
  await waitText(pageA, "#summary_heading", questionC);
  await waitText(pageA, "#summary_heading", "1 saved responses");
  await pageA.locator("#code").fill("sample_long");
  await pageA.locator("#respond").click();
  await waitText(pageA, "#last_result", "Matching saved response replayed.");
  assert.deepEqual(errors, []);
  pass("original R process exits before replacement and stored poll/response replay survives restart");
  console.log(`Browser acceptance: ${checks} checks passed; no browser errors`);
} catch (error) {
  console.error(error);
  throw error;
} finally {
  if (external) await new Promise((resolve) => external.close(resolve));
  if (browser) await browser.close();
  await stop();
}
