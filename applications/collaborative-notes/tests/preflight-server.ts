import { createHash } from "node:crypto";
import { createServer } from "../server/protocol.js";
import { mergeState, seedState } from "../server/binary.js";
import { NOTES, type Storage } from "../shared/spec.js";
const states = new Map(
  NOTES.map((note) => [
    note.id as string,
    seedState(`Start the ${note.title.toLowerCase()} here.\n`),
  ]),
);
const revisions = new Map<string, number>();
const memory: Storage = {
  async load(name) {
    const state = states.get(name);
    if (!state) throw new Error("Missing fixture note.");
    return state;
  },
  async store(name, captured) {
    const previous = states.get(name);
    if (!previous) throw new Error("Missing fixture note.");
    states.set(name, mergeState(previous, captured));
    const revision = (revisions.get(name) ?? 0) + 1;
    revisions.set(name, revision);
    return {
      document: name,
      revision,
      storedAt: new Date().toISOString(),
      capturedHash: createHash("sha256").update(captured).digest("hex"),
    };
  },
};
const server = createServer(memory, process.env.WORKSPACE_TOKEN!);
await server.listen();
process.once("SIGTERM", () => {
  void server.destroy().then(() => process.exit(0));
});
console.log(
  "Native in-memory protocol gate listening; no Cloud/durability claim.",
);
