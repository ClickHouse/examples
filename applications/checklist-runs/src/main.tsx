import { StrictMode, useState, type FormEvent } from "react";
import { createRoot } from "react-dom/client";
import {
  QueryClient,
  QueryClientProvider,
  useMutation,
  useQuery,
  useQueryClient,
} from "@tanstack/react-query";
import {
  request,
  submit,
  type Action,
  type Run,
  type RunDetail,
  type Template,
} from "./api";
import "./style.css";

interface Connection {
  token: string;
  generation: number;
  client: QueryClient;
}

function App() {
  const [connection, setConnection] = useState<Connection | null>(null);
  const [entry, setEntry] = useState("");
  const [generation, setGeneration] = useState(0);
  const [entryError, setEntryError] = useState("");

  function connect(event: FormEvent) {
    event.preventDefault();
    const token = entry.trim();
    if (
      !/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(token) ||
      token.length > 4096
    ) {
      setEntryError("Paste the complete short-lived operator token.");
      return;
    }
    const next = generation + 1;
    setGeneration(next);
    setConnection({
      token,
      generation: next,
      client: new QueryClient({
        defaultOptions: {
          queries: { retry: false, refetchOnWindowFocus: false },
          mutations: { retry: false },
        },
      }),
    });
    setEntry("");
    setEntryError("");
  }

  function disconnect() {
    if (connection) {
      void connection.client.cancelQueries();
      connection.client.clear();
    }
    setConnection(null);
  }

  return (
    <main>
      <header className="masthead">
        <div>
          <span className="eyebrow">Daily operations</span>
          <h1>Checklist runs</h1>
          <p>
            Start from a shared checklist. Keep a clear record of every
            completed step.
          </p>
        </div>
        {connection && (
          <button className="secondary" onClick={disconnect}>
            Disconnect
          </button>
        )}
      </header>
      {connection ? (
        <QueryClientProvider
          client={connection.client}
          key={connection.generation}
        >
          <Dashboard token={connection.token} />
        </QueryClientProvider>
      ) : (
        <section className="connect card">
          <span className="eyebrow">Operator connection</span>
          <h2>Connect to your work</h2>
          <p>
            Paste a short-lived token issued locally for your operator. It stays
            in this tab’s memory; refreshing clears it.
          </p>
          <form onSubmit={connect}>
            <label htmlFor="operator-token">Operator token</label>
            <input
              id="operator-token"
              type="password"
              autoComplete="off"
              value={entry}
              onChange={(e) => setEntry(e.target.value)}
            />
            {entryError && (
              <p role="alert" className="error">
                {entryError}
              </p>
            )}
            <button type="submit">Connect</button>
          </form>
          <p className="muted">
            This local demo has no login provider. Disconnecting clears the
            view; an already-sent action can still finish.
          </p>
        </section>
      )}
      <footer>A shared routine, a durable record.</footer>
    </main>
  );
}

function Dashboard({ token }: { token: string }) {
  const client = useQueryClient();
  const [cursor, setCursor] = useState("0");
  const [selected, setSelected] = useState<string | null>(null);
  const [templateId, setTemplateId] = useState("");
  const [label, setLabel] = useState("");
  const [action, setAction] = useState<Action | null>(null);
  const [success, setSuccess] = useState("");
  const templates = useQuery({
    queryKey: ["templates"],
    queryFn: ({ signal }) =>
      request<Template[]>(token, "templates?order=title.asc", { signal }),
  });
  const runs = useQuery({
    queryKey: ["runs", cursor],
    queryFn: ({ signal }) =>
      request<Run[]>(token, `rpc/list_runs?p_after=${cursor}&p_limit=10`, {
        signal,
      }),
  });
  const detail = useQuery({
    queryKey: ["run", selected],
    enabled: selected !== null,
    queryFn: ({ signal }) =>
      request<RunDetail[]>(
        token,
        `runs?id=eq.${selected}&select=*,run_steps(*),completions(*)&run_steps.order=step_number.asc`,
        { signal },
      ),
  });
  const mutation = useMutation({
    mutationFn: (next: Action) => submit(token, next),
    onSuccess: async (result, submitted) => {
      setSuccess(
        submitted.kind === "start"
          ? "Run started. Your checklist is ready."
          : "Step completion confirmed.",
      );
      if (submitted.kind === "start") {
        setSelected(result.run_id);
        setLabel("");
      }
      await Promise.all([
        client.invalidateQueries({ queryKey: ["runs"] }),
        client.invalidateQueries({ queryKey: ["run", result.run_id] }),
      ]);
      setAction(null);
    },
  });

  function send(next: Action) {
    setSuccess("");
    setAction(next);
    mutation.mutate(next);
  }

  function start(event: FormEvent) {
    event.preventDefault();
    if (action) return;
    send({
      kind: "start",
      payload: {
        p_request_id: crypto.randomUUID(),
        p_template_id: templateId || templates.data?.[0]?.id || "",
        p_label: label,
      },
    });
  }

  const readError = templates.error || runs.error || detail.error;
  const current = detail.data?.[0];
  return (
    <>
      {readError && (
        <p role="alert" className="error notice">
          {readError.message}{" "}
          <button
            className="inline"
            onClick={() => void client.invalidateQueries()}
          >
            Retry reads
          </button>
        </p>
      )}
      {success && (
        <p role="status" className="success notice">
          {success}
        </p>
      )}
      {mutation.isPending && (
        <p role="status" className="notice">
          Confirming your action…
        </p>
      )}
      {mutation.error && action && (
        <section className="error notice" role="alert">
          <strong>{mutation.error.message}</strong>
          <p>
            Retry sends the same request key and captured details. A missing
            response does not prove the action failed.
          </p>
          <button
            onClick={() => mutation.mutate(action)}
            disabled={mutation.isPending}
          >
            Retry same action
          </button>
          <button
            className="secondary"
            disabled={mutation.isPending}
            onClick={() => {
              setAction(null);
              mutation.reset();
              setSuccess(
                "Failed action cleared. Refresh the run before starting another action; clearing does not undo a committed write.",
              );
            }}
          >
            Clear failed action
          </button>
          <small>Request key: {action.payload.p_request_id}</small>
        </section>
      )}
      <div className="workspace">
        <aside>
          <section className="card">
            <span className="eyebrow">New routine</span>
            <h2>Start a run</h2>
            {templates.isPending ? (
              <p>Loading templates…</p>
            ) : (
              <form onSubmit={start}>
                <label htmlFor="template">Checklist</label>
                <select
                  id="template"
                  value={templateId || templates.data?.[0]?.id || ""}
                  disabled={!!action}
                  onChange={(e) => setTemplateId(e.target.value)}
                >
                  {templates.data?.map((t) => (
                    <option key={t.id} value={t.id}>
                      {t.title} · v{t.version}
                    </option>
                  ))}
                </select>
                <label htmlFor="run-label">Run label</label>
                <input
                  id="run-label"
                  required
                  maxLength={80}
                  placeholder="e.g. Tuesday morning"
                  value={label}
                  disabled={!!action}
                  onChange={(e) => setLabel(e.target.value)}
                />
                <button
                  disabled={!!action || !templates.data?.length}
                  type="submit"
                >
                  Start run
                </button>
              </form>
            )}
          </section>
          <section className="card run-list">
            <div className="section-head">
              <h2>Your runs</h2>
              <button
                className="inline"
                disabled={!!action}
                onClick={() => void runs.refetch()}
              >
                Refresh
              </button>
            </div>
            {runs.isPending ? (
              <p>Loading runs…</p>
            ) : !runs.data?.length ? (
              <p className="muted">
                No runs on this page. Start a checklist to begin.
              </p>
            ) : (
              <ul>
                {runs.data.map((run) => (
                  <li key={run.id}>
                    <button
                      className={selected === run.id ? "run selected" : "run"}
                      disabled={!!action}
                      onClick={() => {
                        setSelected(run.id);
                        setSuccess("");
                      }}
                    >
                      <strong>{run.label}</strong>
                      <span>{run.template_title}</span>
                      <small>
                        {run.completed_steps}/{run.total_steps} steps
                        {run.completed_at ? " · Completed" : " · Open"}
                      </small>
                    </button>
                  </li>
                ))}
              </ul>
            )}
            <div className="pagination">
              <button
                className="secondary"
                disabled={!!action || cursor === "0"}
                onClick={() => setCursor("0")}
              >
                First page
              </button>
              <button
                className="secondary"
                disabled={!!action || !runs.data || runs.data.length < 10}
                onClick={() => setCursor(runs.data![runs.data!.length - 1].id)}
              >
                Next page
              </button>
            </div>
            <p className="muted tiny">
              Up to 10 runs per page, in creation order.
            </p>
          </section>
        </aside>
        <section className="card detail">
          {selected === null ? (
            <div className="empty">
              <span className="eyebrow">Ready when you are</span>
              <h2>Choose a run</h2>
              <p>Pick a run to see its saved checklist and completion notes.</p>
            </div>
          ) : detail.isPending ? (
            <p>Loading checklist…</p>
          ) : !current ? (
            <p>
              No accessible run was found. Refresh the list or choose another
              run.
            </p>
          ) : (
            <RunView
              run={current}
              disabled={!!action}
              complete={(step, note) =>
                send({
                  kind: "complete",
                  payload: {
                    p_request_id: crypto.randomUUID(),
                    p_run_id: current.id,
                    p_step_number: step,
                    p_note: note,
                  },
                })
              }
            />
          )}
        </section>
      </div>
      <p className="muted connection-note">
        Token and cached results exist only for this connection. Disconnecting
        does not revoke the token or undo an action already sent.
      </p>
    </>
  );
}

function RunView({
  run,
  disabled,
  complete,
}: {
  run: RunDetail;
  disabled: boolean;
  complete: (step: number, note: string) => void;
}) {
  return (
    <>
      <span className="eyebrow">
        Saved checklist · version {run.template_version}
      </span>
      <div className="section-head">
        <div>
          <h2>{run.label}</h2>
          <p className="muted">{run.template_title}</p>
        </div>
        <span className={run.completed_at ? "badge done" : "badge"}>
          {run.completed_at ? "Completed" : "Open"}
        </span>
      </div>
      <div className="progress-label">
        <strong>
          {run.completed_steps} of {run.total_steps} steps complete
        </strong>
      </div>
      <progress
        max={run.total_steps}
        value={run.completed_steps}
        aria-label="Run progress"
      />
      {run.completed_at && (
        <p className="success">This run is complete. Its record is retained.</p>
      )}
      <ol className="steps">
        {run.run_steps.map((step) => {
          const completion = run.completions.find(
            (c) => c.step_number === step.step_number,
          );
          return (
            <StepCard
              key={`${run.id}-${step.step_number}`}
              title={step.title}
              number={step.step_number}
              note={completion?.note}
              done={!!completion}
              disabled={disabled || !!run.completed_at}
              complete={(note) => complete(step.step_number, note)}
            />
          );
        })}
      </ol>
    </>
  );
}

function StepCard({
  title,
  number,
  note,
  done,
  disabled,
  complete,
}: {
  title: string;
  number: number;
  note?: string;
  done: boolean;
  disabled: boolean;
  complete: (note: string) => void;
}) {
  const [draft, setDraft] = useState("");
  return (
    <li className={done ? "step complete" : "step"}>
      <div className="step-heading">
        <span className="step-number">{done ? "✓" : number}</span>
        <h3>{title}</h3>
      </div>
      {done ? (
        <>
          <span className="completion-label">Completion confirmed</span>
          <p>{note || "No note added."}</p>
        </>
      ) : (
        <form
          onSubmit={(e) => {
            e.preventDefault();
            if (!disabled) complete(draft);
          }}
        >
          <label htmlFor={`note-${number}`}>
            Completion note <span className="muted">(optional)</span>
          </label>
          <input
            id={`note-${number}`}
            maxLength={400}
            value={draft}
            disabled={disabled}
            onChange={(e) => setDraft(e.target.value)}
          />
          <button type="submit" disabled={disabled}>
            Complete step {number}
          </button>
        </form>
      )}
    </li>
  );
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
