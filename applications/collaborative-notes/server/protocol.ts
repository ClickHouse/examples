import { createHash, timingSafeEqual } from "node:crypto";
import { Server } from "@hocuspocus/server";
import * as Y from "yjs";
import {
  allowedDocument,
  MAX_FRAME_BYTES,
  type Storage,
} from "../shared/spec.js";
import { mergeState, validateState } from "./binary.js";

type Context = { workspace: true; document: string };
class DocumentQueue {
  private tail: Promise<void> = Promise.resolve();
  private pending = 0;
  async acquire(): Promise<() => void> {
    if (this.pending >= 32) throw new Error("Note message queue is full.");
    this.pending++;
    const previous = this.tail;
    let done!: () => void;
    this.tail = new Promise<void>((resolve) => {
      done = resolve;
    });
    await previous;
    let released = false;
    return () => {
      if (!released) {
        released = true;
        this.pending--;
        done();
      }
    };
  }
}
export function createServer(storage: Storage, token: string): Server<Context> {
  if (token.length < 32 || token.length > 256)
    throw new Error("Use a private workspace token of 32–256 bytes.");
  const digest = createHash("sha256").update(token).digest();
  const authorized = (candidate: string) =>
    candidate.length <= 256 &&
    timingSafeEqual(digest, createHash("sha256").update(candidate).digest());
  const queues = new Map<string, DocumentQueue>();
  const permits = new WeakMap<Uint8Array, () => void>();
  const sockets = new Set<object>();
  const check = (name: string, context: Context | undefined) => {
    if (
      !allowedDocument(name) ||
      !context?.workspace ||
      context.document !== name
    )
      throw new Error("Workspace authorization required.");
  };
  const server = new Server<Context>({
    address: "127.0.0.1",
    port: 1234,
    stopOnSignals: false,
    quiet: true,
    timeout: 15000,
    debounce: 1500,
    maxDebounce: 5000,
    websocketOptions: { maxPayload: MAX_FRAME_BYTES, perMessageDeflate: false },
    maxUnauthenticatedQueueSize: MAX_FRAME_BYTES,
    maxUnauthenticatedQueueMessages: 32,
    maxPendingDocuments: 1,
    async onUpgrade({ request, socket }) {
      if (
        request.headers.origin !== "http://127.0.0.1:5173" ||
        !["127.0.0.1:5173", "127.0.0.1:1234"].includes(
          request.headers.host ?? "",
        ) ||
        request.url !== "/" ||
        sockets.size >= 12
      ) {
        socket.end(
          "HTTP/1.1 403 Forbidden\r\nConnection: close\r\nContent-Length: 0\r\n\r\n",
        );
        throw undefined;
      }
      sockets.add(socket);
      socket.once("close", () => sockets.delete(socket));
    },
    async onAuthenticate({ documentName, token }) {
      if (!allowedDocument(documentName) || !authorized(token))
        throw new Error("Workspace authorization required.");
      return { workspace: true, document: documentName };
    },
    async onTokenSync({ documentName, token, context }) {
      check(documentName, context);
      if (!authorized(token))
        throw new Error("Workspace authorization required.");
    },
    async onLoadDocument({ documentName, context }) {
      check(documentName, context);
      const bytes = await storage.load(documentName);
      validateState(bytes);
      return bytes;
    },
    async beforeHandleMessage({ documentName, context, update }) {
      check(documentName, context);
      if (update.byteLength > MAX_FRAME_BYTES)
        throw new Error("Message limit exceeded.");
      let queue = queues.get(documentName);
      if (!queue) {
        queue = new DocumentQueue();
        queues.set(documentName, queue);
      }
      permits.set(update, await queue.acquire());
    },
    async afterHandleMessage({ update }) {
      permits.get(update)?.();
      permits.delete(update);
    },
    async beforeSync({ documentName, context, document, type, payload }) {
      check(documentName, context);
      if (type === 1 || type === 2)
        mergeState(Y.encodeStateAsUpdate(document), payload);
    },
    async beforeHandleAwareness({ documentName, context, states }) {
      check(documentName, context);
      // This small plain-text editor omits remote cursor/profile awareness.
      // Drop all client metadata, including the decoder scratch local state.
      states.clear();
    },
    async onStateless({ connection }) {
      connection.sendStateless(
        JSON.stringify({
          type: "info",
          message:
            "Snapshots are periodic; synchronization is not a database receipt.",
        }),
      );
    },
    async onStoreDocument({ documentName, document }) {
      if (!allowedDocument(documentName)) throw new Error("Unknown note.");
      const captured = Y.encodeStateAsUpdate(document);
      validateState(captured);
      try {
        const receipt = await storage.store(documentName, captured);
        document.broadcastStateless(
          JSON.stringify({ type: "stored", receipt }),
        );
      } catch {
        document.broadcastStateless(
          JSON.stringify({ type: "store-failed", document: documentName }),
        );
        throw new Error(
          "Database snapshot storage failed; uncommitted changes remain in memory.",
        );
      }
    },
  });
  server.httpServer.requestTimeout = 10000;
  server.httpServer.headersTimeout = 5000;
  server.httpServer.maxHeadersCount = 32;
  return server;
}
