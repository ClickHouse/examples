import assert from "node:assert/strict";
import test from "node:test";
import * as Y from "yjs";
import { mergeState, seedState, validateState } from "../server/binary.js";
test("Yjs binary merge retains insertions and deletions through reordered repeated snapshots", () => {
  const baseline = seedState("ABC");
  const writer = new Y.Doc();
  Y.applyUpdate(writer, baseline);
  const text = writer.getText("content");
  text.insert(3, "D");
  const inserted = Y.encodeStateAsUpdate(writer);
  text.delete(1, 1);
  const deleted = Y.encodeStateAsUpdate(writer);
  const final = mergeState(
    mergeState(mergeState(deleted, baseline), inserted),
    deleted,
  );
  const loaded = new Y.Doc();
  Y.applyUpdate(loaded, final);
  assert.equal(loaded.getText("content").toString(), "ACD");
  writer.destroy();
  loaded.destroy();
});
test("unexpected roots, rich text and missing CRDT dependencies are rejected", () => {
  const orphan = new Y.Doc();
  orphan.getText("content").insert(0, "unknown");
  const vector = Y.encodeStateVector(orphan);
  orphan.getText("content").insert(7, "missing");
  assert.throws(() => validateState(Y.encodeStateAsUpdate(orphan, vector)));
  orphan.destroy();
  const doc = new Y.Doc();
  doc.getMap("unexpected").set("x", "no");
  assert.throws(() => validateState(Y.encodeStateAsUpdate(doc)));
  doc.destroy();
  const rich = new Y.Doc();
  rich.getText("content").insertEmbed(0, { html: "unsafe" });
  assert.throws(() => validateState(Y.encodeStateAsUpdate(rich)));
  rich.destroy();
});
test("rendered text and binary state limits are distinct", () => {
  assert.throws(() => validateState(seedState("x".repeat(10001))));
  assert.throws(() => validateState(new Uint8Array(512 * 1024 + 1)));
  validateState(seedState("Valid 🚀\nplain note"));
});
