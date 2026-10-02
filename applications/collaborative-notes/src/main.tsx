import React, { useEffect, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import { EditorState } from "@codemirror/state";
import { EditorView, keymap } from "@codemirror/view";
import { yCollab, yUndoManagerKeymap } from "y-codemirror.next";
import { HocuspocusProvider } from "@hocuspocus/provider";
import * as Y from "yjs";
import { NOTES, type StoreReceipt } from "../shared/spec.js";
import "./style.css";

function Editor({ name, token }: { name: string; token: string }) {
  const element = useRef<HTMLDivElement>(null);
  const provider = useRef<HocuspocusProvider | null>(null);
  const [status, setStatus] = useState("Connecting");
  const [synced, setSynced] = useState(false);
  const [paused, setPaused] = useState(false);
  const [receipt, setReceipt] = useState<StoreReceipt | null>(null);
  const [failed, setFailed] = useState(false);
  const [authFailed, setAuthFailed] = useState(false);
  useEffect(() => {
    const document = new Y.Doc();
    const text = document.getText("content");
    const undo = new Y.UndoManager(text);
    const connection = new HocuspocusProvider({
      url: `ws://${window.location.host}/collab`,
      name,
      document,
      token,
      awareness: null,
      onStatus: ({ status }) => {
        setStatus(status);
        if (status !== "connected") setSynced(false);
      },
      onSynced: ({ state }) => setSynced(state),
      onAuthenticationFailed: () => {
        setAuthFailed(true);
        setStatus("Authentication failed");
      },
      onStateless: ({ payload }) => {
        try {
          const message = JSON.parse(payload);
          if (message.type === "stored" && message.receipt?.document === name) {
            setReceipt(message.receipt);
            setFailed(false);
          }
          if (message.type === "store-failed" && message.document === name)
            setFailed(true);
        } catch {
          /* Ignore non-receipt messages. */
        }
      },
    });
    provider.current = connection;
    const view = new EditorView({
      parent: element.current!,
      state: EditorState.create({
        doc: text.toString(),
        extensions: [
          EditorView.lineWrapping,
          EditorView.contentAttributes.of({ "aria-label": "Note text" }),
          keymap.of(yUndoManagerKeymap),
          yCollab(text, null, { undoManager: undo }),
          EditorView.theme({
            "&": { fontSize: "17px" },
            ".cm-content": {
              fontFamily: "inherit",
              minHeight: "290px",
              padding: "20px",
            },
            ".cm-scroller": { fontFamily: "inherit", lineHeight: "1.65" },
            "&.cm-focused": { outline: "none" },
          }),
        ],
      }),
    });
    return () => {
      provider.current = null;
      view.destroy();
      connection.destroy();
      undo.destroy();
      document.destroy();
    };
  }, [name, token]);
  function pause() {
    provider.current?.disconnect();
    setPaused(true);
    setSynced(false);
  }
  function resume() {
    provider.current?.connect();
    setPaused(false);
  }
  return (
    <section className="note">
      <div className="note-top">
        <div>
          <p className="eyebrow">Shared note</p>
          <h2>{NOTES.find((note) => note.id === name)?.title}</h2>
        </div>
        <span className="status">
          {status === "connected"
            ? synced
              ? "Connected and synchronized"
              : "Catching up"
            : paused
              ? "Offline in this tab"
              : status}
        </span>
      </div>
      <div className="editor" ref={element} />
      <div className="note-bottom">
        <button onClick={paused ? resume : pause} disabled={authFailed}>
          {paused ? "Reconnect" : "Work offline"}
        </button>
        <span>Undo / redo: Ctrl+Z / Ctrl+Shift+Z</span>
      </div>
      {authFailed && (
        <p role="alert" className="error">
          The workspace token was rejected. Leave this workspace and enter a
          valid token.
        </p>
      )}
      {paused && (
        <p className="notice">
          Offline edits stay in this tab. Reconnect before leaving or switching
          notes.
        </p>
      )}
      <div className="persistence">
        <strong>Periodic database snapshots</strong>
        <p>
          {failed
            ? "The last storage attempt failed. Shared edits are not confirmed stored and may be lost if the server stops."
            : receipt
              ? `A snapshot was committed at ${new Date(receipt.storedAt).toLocaleTimeString()}. Later edits may still be waiting.`
              : "Connected editors sync immediately. Database storage happens separately, every few seconds."}
        </p>
      </div>
    </section>
  );
}
function App() {
  const [entry, setEntry] = useState("");
  const [token, setToken] = useState<string | null>(null);
  const [name, setName] = useState<string>(NOTES[0].id);
  const [session, setSession] = useState(0);
  function connect(event: React.FormEvent) {
    event.preventDefault();
    if (entry.length < 32 || entry.length > 256) return;
    setToken(entry);
    setEntry("");
    setSession((value) => value + 1);
  }
  return (
    <main>
      <header>
        <div className="mark">n</div>
        <div>
          <p className="eyebrow">A trusted shared workspace</p>
          <h1>Notes, together.</h1>
          <p>Keep the plan in one place while everyone adds their part.</p>
        </div>
      </header>
      {!token ? (
        <form className="connect" onSubmit={connect}>
          <h2>Enter the workspace</h2>
          <label htmlFor="token">Workspace token</label>
          <input
            id="token"
            type="password"
            autoComplete="off"
            value={entry}
            onChange={(event) => setEntry(event.target.value)}
            minLength={32}
            maxLength={256}
            required
          />
          <button>Connect</button>
          <p>
            The token stays in this tab’s memory. Use the local fixture token
            supplied by your workspace operator.
          </p>
        </form>
      ) : (
        <div className="workspace">
          <nav aria-label="Notes">
            <p className="eyebrow">Three shared notes</p>
            {NOTES.map((note) => (
              <button
                key={note.id}
                className={name === note.id ? "selected" : ""}
                onClick={() => setName(note.id)}
              >
                {note.title}
              </button>
            ))}
            <div className="nav-help">
              Reconnect before switching notes. Leaving or switching discards
              this tab’s unsynchronized edits.
            </div>
            <button className="leave" onClick={() => setToken(null)}>
              Leave workspace
            </button>
          </nav>
          <Editor key={`${session}:${name}`} name={name} token={token} />
        </div>
      )}
      <footer>
        Live synchronization is separate from periodic storage. A sudden server
        loss can lose edits that were never committed.
      </footer>
    </main>
  );
}
createRoot(document.getElementById("root")!).render(<App />);
