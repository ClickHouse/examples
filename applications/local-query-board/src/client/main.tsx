import React, { useState } from "react";
import { createRoot } from "react-dom/client";
import { useLiveQuery } from "@tanstack/react-db";
import { eq } from "@tanstack/db";
import { tasks, projects } from "./collections";
import { statuses, priorities } from "../shared";
import "./style.css";
function App() {
  const [filter, setFilter] = useState("all");
  const [projectFilter, setProjectFilter] = useState("all");
  const [title, setTitle] = useState("");
  const [project, setProject] = useState(
    "10000000-0000-4000-8000-000000000001",
  );
  const [priority, setPriority] =
    useState<(typeof priorities)[number]>("medium");
  const [pending, setPending] = useState(false);
  const [message, setMessage] = useState("");
  const { data: projectRows = [] } = useLiveQuery((q) =>
    q.from({ project: projects }).orderBy(({ project }) => project.name),
  );
  const {
    data: rows = [],
    isLoading,
    isError,
  } = useLiveQuery(
    (q) => {
      let query = q
        .from({ task: tasks })
        .join(
          { project: projects },
          ({ task, project }) => eq(task.project_id, project.id),
          "inner",
        );
      if (filter !== "all")
        query = query.where(({ task }) => eq(task.status, filter));
      if (projectFilter !== "all")
        query = query.where(({ task }) => eq(task.project_id, projectFilter));
      return query
        .orderBy(({ task }) => task.title)
        .select(({ task, project }) => ({
          ...task,
          project_name: project.name,
          project_color: project.color,
        }));
    },
    [filter, projectFilter],
  );
  async function write(
    url: string,
    method: string,
    body: unknown,
    onCommitted?: () => void,
  ) {
    setPending(true);
    setMessage("Saving to Postgres…");
    try {
      const response = await fetch(url, {
        method,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error);
      onCommitted?.();
      setMessage("Committed. Waiting for the live stream…");
      try {
        await tasks.utils.awaitTxId(result.txid, 15000);
        setMessage("Saved and synchronized");
      } catch {
        setMessage(
          "Saved to Postgres. The live stream is catching up; please do not submit it again.",
        );
      }
      return true;
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Could not save");
      return false;
    } finally {
      setPending(false);
    }
  }
  return (
    <main>
      <header>
        <a className="brand" href="/">
          ◈ FIELDWORK
        </a>
        <span className="edition">LIVE PLANNING / 01</span>
      </header>
      <section className="intro">
        <div>
          <p className="eyebrow">A shared place to move work forward</p>
          <h1>
            Small tasks.
            <br />
            <em>Shared momentum.</em>
          </h1>
          <p className="lede">
            Plan across projects. Edits flow from Postgres into every open
            board.
          </p>
        </div>
        <aside>
          <span className="pulse" />
          Electric → TanStack DB<p>Local queries · live changes</p>
          <strong>
            {isLoading ? "Connecting…" : `${rows.length} tasks in view`}
          </strong>
        </aside>
      </section>
      <section className="toolbar">
        <div>
          <label>
            Status
            <select
              aria-label="Status filter"
              value={filter}
              onChange={(e) => setFilter(e.target.value)}
            >
              <option value="all">All statuses</option>
              {statuses.map((s) => (
                <option key={s}>{s}</option>
              ))}
            </select>
          </label>
          <label>
            Project
            <select
              aria-label="Project filter"
              value={projectFilter}
              onChange={(e) => setProjectFilter(e.target.value)}
            >
              <option value="all">All projects</option>
              {projectRows.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name}
                </option>
              ))}
            </select>
          </label>
        </div>
        <span>Filters run locally on the synced collections</span>
      </section>
      {isError && (
        <p role="alert">
          The live stream could not load. Check the app and Electric logs.
        </p>
      )}
      <section className="board">
        {statuses.map((status) => (
          <div className="column" key={status}>
            <h2>
              <span>
                {status === "todo"
                  ? "To do"
                  : status === "doing"
                    ? "In progress"
                    : "Done"}
              </span>
              <b>{rows.filter((t) => t.status === status).length}</b>
            </h2>
            {rows
              .filter((t) => t.status === status)
              .map((t) => (
                <article className="task" key={t.id} data-testid="task">
                  <div className="task-meta">
                    <span style={{ color: t.project_color }}>
                      {t.project_name}
                    </span>
                    <small>r{t.revision}</small>
                  </div>
                  <h3>{t.title}</h3>
                  <footer>
                    <label>
                      <span className="sr">Status for {t.title}</span>
                      <select
                        aria-label={`Status for ${t.title}`}
                        value={t.status}
                        disabled={pending}
                        onChange={(e) =>
                          void write(`/api/tasks/${t.id}`, "PATCH", {
                            revision: t.revision,
                            status: e.target.value,
                            priority: t.priority,
                          })
                        }
                      >
                        {statuses.map((s) => (
                          <option key={s}>{s}</option>
                        ))}
                      </select>
                    </label>
                    <label>
                      <span className="sr">Priority for {t.title}</span>
                      <select
                        aria-label={`Priority for ${t.title}`}
                        value={t.priority}
                        disabled={pending}
                        onChange={(e) =>
                          void write(`/api/tasks/${t.id}`, "PATCH", {
                            revision: t.revision,
                            status: t.status,
                            priority: e.target.value,
                          })
                        }
                      >
                        {priorities.map((s) => (
                          <option key={s}>{s}</option>
                        ))}
                      </select>
                    </label>
                  </footer>
                </article>
              ))}
            {!isLoading && !rows.some((t) => t.status === status) && (
              <p className="empty">Nothing here yet.</p>
            )}
          </div>
        ))}
      </section>
      <form
        className="compose"
        onSubmit={async (e) => {
          e.preventDefault();
          await write(
            "/api/tasks",
            "POST",
            { title, project_id: project, priority },
            () => setTitle(""),
          );
        }}
      >
        <div>
          <p className="eyebrow">Next on the list</p>
          <h2>Add a task</h2>
        </div>
        <label className="title-field">
          Task title
          <input
            aria-label="Task title"
            placeholder="What needs to happen?"
            value={title}
            required
            maxLength={120}
            disabled={pending}
            onChange={(e) => setTitle(e.target.value)}
          />
        </label>
        <label>
          Project
          <select
            aria-label="New task project"
            value={project}
            disabled={pending}
            onChange={(e) => setProject(e.target.value)}
          >
            {projectRows.map((p) => (
              <option key={p.id} value={p.id}>
                {p.name}
              </option>
            ))}
          </select>
        </label>
        <label>
          Priority
          <select
            aria-label="New task priority"
            value={priority}
            disabled={pending}
            onChange={(e) => setPriority(e.target.value as typeof priority)}
          >
            {priorities.map((s) => (
              <option key={s}>{s}</option>
            ))}
          </select>
        </label>
        <button disabled={pending || isLoading}>Add task ↗</button>
      </form>
      <p className="notice" role="status">
        {message ||
          "Open a second tab to see changes arrive through the live stream."}
      </p>
      <div className="footnote">
        A trusted local workbench · server writes remain authoritative · no
        offline writes
      </div>
    </main>
  );
}
createRoot(document.getElementById("root")!).render(<App />);
