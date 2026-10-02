import assert from "node:assert/strict";
import WebSocket from "ws";
import {
  HocuspocusProvider,
  HocuspocusProviderWebsocket,
} from "@hocuspocus/provider";
import * as Y from "yjs";
async function rejected(headers) {
  await new Promise((resolve, reject) => {
    const ws = new WebSocket("ws://127.0.0.1:1234", { headers });
    ws.once("unexpected-response", (_req, res) => {
      assert.equal(res.statusCode, 403);
      res.resume();
      ws.terminate();
      resolve();
    });
    ws.once("open", () => {
      ws.close();
      reject(new Error("Unexpected upgrade"));
    });
    ws.once("error", () => {});
    setTimeout(
      () => reject(new Error("Upgrade rejection timeout")),
      5000,
    ).unref();
  });
}
class LocalSocket extends WebSocket {
  constructor(url) {
    super(url, { headers: { Origin: "http://127.0.0.1:5173" } });
  }
}
async function denied(name, token) {
  const doc = new Y.Doc();
  const websocket = new HocuspocusProviderWebsocket({
    url: "ws://127.0.0.1:1234",
    WebSocketPolyfill: LocalSocket,
  });
  let resolve;
  const failed = new Promise((r) => (resolve = r));
  const provider = new HocuspocusProvider({
    websocketProvider: websocket,
    name,
    document: doc,
    token,
    awareness: null,
    onAuthenticationFailed: () => resolve(),
  });
  provider.attach();
  try {
    await Promise.race([
      failed,
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error("Auth rejection timeout")), 7000),
      ),
    ]);
    assert.equal(doc.getText("content").length, 0);
  } finally {
    provider.destroy();
    websocket.destroy();
    doc.destroy();
  }
}
await rejected({ Origin: "https://foreign.invalid" });
await rejected({ Origin: "http://127.0.0.1:5173", Host: "foreign.invalid" });
await denied("release-planning", "x".repeat(43));
await denied("foreign-note", process.env.WORKSPACE_TOKEN);
await new Promise((resolve, reject) => {
  const ws = new LocalSocket("ws://127.0.0.1:1234");
  ws.once("open", () => ws.send(Buffer.alloc(65537)));
  ws.once("close", (code) => {
    assert.equal(code, 1009);
    resolve();
  });
  ws.on("error", () => {});
  setTimeout(
    () => reject(new Error("Payload rejection timeout")),
    5000,
  ).unref();
});
console.log(
  "PASS foreign Origin and Host reject upgrades; invalid token and unknown document cannot load; over-limit raw frame closes with1009.",
);
