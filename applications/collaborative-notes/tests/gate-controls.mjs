import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import {
  HocuspocusProvider,
  HocuspocusProviderWebsocket,
} from "@hocuspocus/provider";
import WebSocket from "ws";
import * as Y from "yjs";
import { createServer } from "../dist-server/server/protocol.js";
import { mergeState, seedState } from "../dist-server/server/binary.js";
const token = process.env.WORKSPACE_TOKEN;
let stored = seedState("Safe");
const memory = {
  async load() {
    return stored;
  },
  async store(name, captured) {
    stored = mergeState(stored, captured);
    return {
      document: name,
      revision: 1,
      storedAt: new Date().toISOString(),
      capturedHash: createHash("sha256").update(captured).digest("hex"),
    };
  },
};
const server = createServer(memory, token);
await server.listen();
class LocalSocket extends WebSocket {
  constructor(url) {
    super(url, { headers: { Origin: "http://127.0.0.1:5173" } });
  }
}
async function connect() {
  const doc = new Y.Doc();
  let resolve;
  const ready = new Promise((r) => (resolve = r));
  const websocket = new HocuspocusProviderWebsocket({
    url: "ws://127.0.0.1:1234",
    WebSocketPolyfill: LocalSocket,
  });
  const provider = new HocuspocusProvider({
    websocketProvider: websocket,
    name: "meeting-notes",
    document: doc,
    token,
    onSynced: ({ state }) => {
      if (state) resolve();
    },
  });
  provider.attach();
  await Promise.race([
    ready,
    new Promise((_, reject) =>
      setTimeout(
        () => reject(new Error("Native provider sync timeout")),
        10000,
      ),
    ),
  ]);
  return {
    doc,
    provider,
    websocket,
    destroy() {
      provider.destroy();
      websocket.destroy();
      doc.destroy();
    },
  };
}
async function wait(predicate) {
  const end = Date.now() + 10000;
  while (Date.now() < end) {
    if (predicate()) return;
    await new Promise((r) => setTimeout(r, 50));
  }
  throw new Error("Control did not complete.");
}
try {
  const good = await connect();
  const live = server.hocuspocus.documents.get("meeting-notes");
  const before = Y.encodeStateAsUpdate(live);
  for (const invalid of ["unexpected", "oversize", "pending", "unexpected"]) {
    const bad = await connect();
    let rejected = false;
    bad.websocket.on("disconnect", () => {
      rejected = true;
    });
    bad.provider.on("close", () => {
      rejected = true;
    });
    if (invalid === "unexpected")
      bad.doc.getMap("wrong-root").set("evil", "ignored");
    else if (invalid === "oversize")
      bad.doc.getText("content").insert(0, "x".repeat(10001));
    else {
      const orphan = new Y.Doc();
      orphan.getText("content").insert(0, "unknown");
      const vector = Y.encodeStateVector(orphan);
      orphan.getText("content").insert(7, " missing");
      const update = Y.encodeStateAsUpdate(orphan, vector);
      orphan.destroy();
      const varUint = (value) => {
        const bytes = [];
        do {
          let byte = value & 127;
          value = Math.floor(value / 128);
          if (value) byte |= 128;
          bytes.push(byte);
        } while (value);
        return Buffer.from(bytes);
      };
      const name = Buffer.from("meeting-notes");
      bad.websocket.webSocket.send(
        Buffer.concat([
          varUint(name.length),
          name,
          Buffer.from([0, 2]),
          varUint(update.length),
          Buffer.from(update),
        ]),
      );
    }
    await wait(() => rejected);
    bad.destroy();
    assert.equal(live.getText("content").toString(), "Safe");
    assert.deepEqual(Y.encodeStateAsUpdate(live), before);
  }
  good.doc.getText("content").insert(4, " accepted");
  await wait(() => live.getText("content").toString() === "Safe accepted");
  assert(!live.store.pendingStructs && !live.store.pendingDs);
  good.destroy();
  console.log(
    "Rejected repeated invalid/oversized updates leave unchanged bounded state/no pending structs; valid same-note edit succeeds afterward (permit release proven).",
  );
} finally {
  await server.destroy();
}
