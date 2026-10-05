import React, { useEffect, useMemo, useState, useRef } from "react";
import { createRoot } from "react-dom/client";
import { ApolloClient, HttpLink, InMemoryCache } from "@apollo/client";
import { ApolloProvider, useQuery, useMutation } from "@apollo/client/react";
import {
  BoardDocument,
  ProjectDocument,
  CreateProjectDocument,
  CreateTaskDocument,
  UpdateTaskDocument,
} from "./operations.ts";
import "./style.css";
type Session = {
  userId: string;
  email: string;
  workspaceId: string;
  workspaceName: string;
};
function App() {
  const [session, setSession] = useState<Session | null>(null);
  const [checking, setChecking] = useState(true);
  const [epoch, setEpoch] = useState(0);
  const [authError, setAuthError] = useState("");
  const bundle = useMemo(() => {
    const controller = new AbortController();
    return {
      controller,
      client: new ApolloClient({
        link: new HttpLink({
          uri: "/graphql",
          credentials: "same-origin",
          fetch: (input, init) =>
            fetch(input, { ...init, signal: controller.signal }),
        }),
        cache: new InMemoryCache(),
      }),
    };
  }, [epoch]);
  const channel = useMemo(
    () => new BroadcastChannel("common-ground-session"),
    [],
  );
  const generation = useRef(0);
  const currentBundle = useRef(bundle);
  currentBundle.current = bundle;
  async function refreshSession() {
    const request = ++generation.current;
    setChecking(true);
    const previous = currentBundle.current;
    previous.controller.abort();
    previous.client.stop();
    await previous.client.clearStore();
    try {
      const response = await fetch("/api/me");
      if (!response.ok) throw new Error("Session request failed");
      const value = await response.json();
      if (request !== generation.current) return;
      setSession(value.session);
      setEpoch((e) => e + 1);
    } catch {
      if (request !== generation.current) return;
      setAuthError("Could not read your session. Reload to try again.");
      setSession(null);
    } finally {
      if (request === generation.current) setChecking(false);
    }
  }
  useEffect(() => {
    void refreshSession();
    return () => {
      generation.current++;
      channel.close();
    };
  }, []);
  useEffect(() => {
    channel.onmessage = () => void refreshSession();
    return () => {
      channel.onmessage = null;
    };
  }, []);
  useEffect(
    () => () => {
      bundle.controller.abort();
      bundle.client.stop();
    },
    [bundle],
  );
  async function signIn(email: string, password: string) {
    setAuthError("");
    try {
      const response = await fetch("/api/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, password }),
      });
      if (!response.ok) {
        setAuthError("Email or password did not match.");
        return;
      }
      await refreshSession();
      channel.postMessage("changed");
    } catch {
      setAuthError("Could not sign in. Check the connection and try again.");
    }
  }
  async function signOut() {
    setAuthError("");
    try {
      const response = await fetch("/api/logout", { method: "POST" });
      if (!response.ok) throw new Error("Logout failed");
      await refreshSession();
      channel.postMessage("changed");
    } catch {
      setAuthError("Could not sign out. Check the connection and try again.");
    }
  }
  return (
    <main>
      <header>
        <a href="/" className="brand">
          ◌ COMMON GROUND
        </a>
        <span className="edition">WORKSPACE JOURNAL / 01</span>
      </header>
      {checking ? (
        <section className="login">
          <h1>Checking your session…</h1>
        </section>
      ) : session ? (
        <ApolloProvider client={bundle.client}>
          <Board key={epoch} session={session} signOut={signOut} />
          {authError && <p role="alert">{authError}</p>}
        </ApolloProvider>
      ) : (
        <Login error={authError} signIn={signIn} />
      )}
      <div className="footnote">
        A local synthetic-account demo · SQL-derived GraphQL · Postgres
        row-level security
      </div>
    </main>
  );
}
function Login({
  error,
  signIn,
}: {
  error: string;
  signIn: (email: string, password: string) => Promise<void>;
}) {
  const [email, setEmail] = useState("alice@example.test");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  return (
    <section className="login">
      <p className="eyebrow">A place for each team’s work</p>
      <h1>
        Different workspaces.
        <br />
        <em>A common ground.</em>
      </h1>
      <p className="lede">
        Sign in with a synthetic demo account. Its verified session determines
        which rows Postgres allows you to see.
      </p>
      <form
        onSubmit={async (e) => {
          e.preventDefault();
          setBusy(true);
          try {
            await signIn(email, password);
          } finally {
            setBusy(false);
          }
        }}
      >
        <label>
          Account
          <select
            aria-label="Account"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
          >
            <option value="alice@example.test">Alice · Riverside Studio</option>
            <option value="bob@example.test">Bob · Summit Team</option>
          </select>
        </label>
        <label>
          Password
          <input
            aria-label="Password"
            type="password"
            required
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />
        </label>
        <button disabled={busy}>Sign in ↗</button>
      </form>
      <p className="demo">
        Demo passwords: Alice <code>river-demo</code> · Bob{" "}
        <code>summit-demo</code>
      </p>
      {error && <p role="alert">{error}</p>}
    </section>
  );
}
function Board({
  session,
  signOut,
}: {
  session: Session;
  signOut: () => Promise<void>;
}) {
  const { data, loading, error, fetchMore } = useQuery(BoardDocument);
  const [selected, setSelected] = useState<string | null>(null);
  const [taskTitle, setTaskTitle] = useState("");
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [message, setMessage] = useState("");
  const [createProject, { loading: creating }] = useMutation(
    CreateProjectDocument,
    { refetchQueries: [BoardDocument], awaitRefetchQueries: true },
  );
  const [createTask, { loading: adding }] = useMutation(CreateTaskDocument, {
    refetchQueries: ["ProjectNotebook"],
    awaitRefetchQueries: true,
  });
  const [updateTask, { loading: updating }] = useMutation(UpdateTaskDocument);
  const rows = data?.allProjects.nodes ?? [];
  const selectedId = selected ?? rows[0]?.rowId;
  const detail = useQuery(ProjectDocument, {
    variables: { rowId: selectedId ?? "" },
    skip: !selectedId,
  });
  const project = detail.data?.projectByRowId;
  const tasks = project?.tasksByProjectIdAndWorkspaceId;
  const busy = creating || adding || updating;
  async function moreProjects() {
    try {
      await fetchMore({
        variables: { after: data?.allProjects.pageInfo.endCursor },
        updateQuery: (previous, { fetchMoreResult }) => ({
          allProjects: {
            ...fetchMoreResult.allProjects,
            nodes: [
              ...previous.allProjects.nodes,
              ...fetchMoreResult.allProjects.nodes.filter(
                (p) =>
                  !previous.allProjects.nodes.some((old) => old.id === p.id),
              ),
            ],
          },
        }),
      });
    } catch {
      setMessage("Could not load more projects. Try again.");
    }
  }
  async function moreTasks() {
    try {
      await detail.fetchMore({
        variables: { after: tasks?.pageInfo.endCursor },
        updateQuery: (previous, { fetchMoreResult }) => {
          const old = previous.projectByRowId;
          const next = fetchMoreResult.projectByRowId;
          if (!old || !next) return fetchMoreResult;
          return {
            projectByRowId: {
              ...next,
              tasksByProjectIdAndWorkspaceId: {
                ...next.tasksByProjectIdAndWorkspaceId,
                nodes: [
                  ...old.tasksByProjectIdAndWorkspaceId.nodes,
                  ...next.tasksByProjectIdAndWorkspaceId.nodes.filter(
                    (t) =>
                      !old.tasksByProjectIdAndWorkspaceId.nodes.some(
                        (o) => o.id === t.id,
                      ),
                  ),
                ],
              },
            },
          };
        },
      });
    } catch {
      setMessage("Could not load more tasks. Try again.");
    }
  }
  async function operation(fn: () => Promise<unknown>, success: string) {
    setMessage("");
    try {
      await fn();
      setMessage(success);
      return true;
    } catch {
      setMessage(
        "The operation could not be completed. Review the fields and try again.",
      );
      return false;
    }
  }
  return (
    <>
      <section className="intro">
        <div>
          <p className="eyebrow">Your team’s working notebook</p>
          <h1>{session.workspaceName}</h1>
          <p className="lede">
            Keep projects clear, and the next step close at hand.
          </p>
        </div>
        <aside>
          <span>{session.email}</span>
          <button className="quiet" onClick={() => void signOut()}>
            Switch workspace
          </button>
          <p>{data?.allProjects.totalCount ?? 0} projects in this workspace</p>
        </aside>
      </section>

      {error && (
        <p role="alert">
          Could not load the workspace. Sign in again to retry.
        </p>
      )}
      {loading ? (
        <p className="lede">Loading projects…</p>
      ) : (
        <section className="workspace">
          <nav>
            <p className="eyebrow">
              Projects{" "}
              <b>
                {rows.length} of {data?.allProjects.totalCount ?? 0}
              </b>
            </p>
            {rows.map((p) => (
              <button
                className={
                  p.rowId === project?.rowId ? "project active" : "project"
                }
                key={p.id}
                onClick={() => {
                  setSelected(p.rowId);
                  setTaskTitle("");
                }}
              >
                <strong>{p.name}</strong>
                <span>{p.description || "Open notebook"}</span>
              </button>
            ))}
            {data?.allProjects.pageInfo.hasNextPage && (
              <button className="quiet" onClick={() => void moreProjects()}>
                Load more projects
              </button>
            )}
            <form
              className="project-form"
              onSubmit={async (e) => {
                e.preventDefault();
                let id: string | undefined;
                if (
                  await operation(async () => {
                    const result = await createProject({
                      variables: { name, description },
                    });
                    id = result.data?.createProject.project.rowId;
                  }, "Project saved")
                ) {
                  setName("");
                  setDescription("");
                  if (id) setSelected(id);
                }
              }}
            >
              <h3>Start a project</h3>
              <label>
                Name
                <input
                  aria-label="New project name"
                  value={name}
                  required
                  maxLength={80}
                  disabled={busy}
                  onChange={(e) => setName(e.target.value)}
                />
              </label>
              <label>
                Description
                <input
                  aria-label="New project description"
                  value={description}
                  maxLength={500}
                  disabled={busy}
                  onChange={(e) => setDescription(e.target.value)}
                />
              </label>
              <button disabled={busy}>Create project ↗</button>
            </form>
          </nav>
          <div className="detail">
            {detail.loading && !project ? (
              <p>Loading notebook…</p>
            ) : detail.error ? (
              <p role="alert">Could not load this project.</p>
            ) : project ? (
              <>
                <p className="eyebrow">Project notebook</p>
                <h2>{project.name}</h2>
                <p className="description">
                  {project.description ||
                    "A fresh space for the team’s next steps."}
                </p>
                <div className="task-header">
                  <span>Next steps</span>
                  <span>
                    {tasks?.nodes.length} of {tasks?.totalCount} tasks ·{" "}
                    {tasks?.nodes.filter((t) => t.done).length} loaded complete
                  </span>
                </div>
                {project.tasksByProjectIdAndWorkspaceId.nodes.map((task) => (
                  <label
                    className={task.done ? "task complete" : "task"}
                    key={task.id}
                  >
                    <input
                      aria-label={`Complete ${task.title}`}
                      type="checkbox"
                      checked={task.done}
                      disabled={busy}
                      onChange={(e) =>
                        void operation(
                          () =>
                            updateTask({
                              variables: {
                                rowId: task.rowId,
                                done: e.target.checked,
                              },
                            }),
                          "Task updated",
                        )
                      }
                    />
                    <span>{task.title}</span>
                    <small>{task.done ? "done" : "open"}</small>
                  </label>
                ))}
                {project.tasksByProjectIdAndWorkspaceId.nodes.length === 0 && (
                  <p className="empty">
                    No tasks yet. Add the first next step below.
                  </p>
                )}
                {tasks?.pageInfo.hasNextPage && (
                  <button className="quiet" onClick={() => void moreTasks()}>
                    Load more tasks
                  </button>
                )}
                <form
                  className="task-form"
                  onSubmit={async (e) => {
                    e.preventDefault();
                    if (
                      await operation(
                        () =>
                          createTask({
                            variables: {
                              projectId: project.rowId,
                              title: taskTitle,
                            },
                          }),
                        "Task saved",
                      )
                    )
                      setTaskTitle("");
                  }}
                >
                  <label>
                    Next step
                    <input
                      aria-label="New task title"
                      value={taskTitle}
                      required
                      maxLength={120}
                      disabled={busy}
                      placeholder="What needs to happen?"
                      onChange={(e) => setTaskTitle(e.target.value)}
                    />
                  </label>
                  <button disabled={busy}>Add task ↗</button>
                </form>
              </>
            ) : (
              <>
                <h2>A clear starting point.</h2>
                <p>Create a project to begin this workspace.</p>
              </>
            )}
          </div>
        </section>
      )}
      <p className="notice" role="status">
        {message ||
          "Only this session’s workspace is visible. Switching sessions replaces the Apollo cache."}
      </p>
    </>
  );
}
createRoot(document.getElementById("root")!).render(<App />);
