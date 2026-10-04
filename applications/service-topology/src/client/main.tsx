import React from "react";
import { createRoot } from "react-dom/client";
import {
  ReactFlow,
  Background,
  Controls,
  Handle,
  Position,
  MarkerType,
  type NodeProps,
  type Node,
  type ReactFlowInstance,
} from "@xyflow/react";
import { api } from "./api";
import { useGraph, documentFromState } from "./store";
import {
  DEMO_GRAPH_ID,
  type ServiceKind,
  type ServiceNode,
  type ServiceEdge,
} from "../shared/types";
import "@xyflow/react/dist/style.css";
import "./style.css";

const kinds: ServiceKind[] = ["web", "api", "worker", "database"];
function ServiceCard({
  id,
  data,
  selected,
}: NodeProps<Node<{ label: string; kind: ServiceKind }, "service">>) {
  return (
    <div
      className={"service-card " + data.kind + (selected ? " selected" : "")}
      data-testid="service-card"
    >
      <Handle type="target" position={Position.Left} />
      <div className="service-kind">{data.kind}</div>
      <strong>{data.label || "Untitled service"}</strong>
      <span className="service-ref">{id.slice(0, 8)}</span>
      <Handle type="source" position={Position.Right} />
    </div>
  );
}
const nodeTypes = { service: ServiceCard };

function App() {
  const state = useGraph();
  const [selected, select] = React.useState<string>();
  const [kind, setKind] = React.useState<ServiceKind>("api");
  const [flow, setFlow] =
    React.useState<ReactFlowInstance<ServiceNode, ServiceEdge>>();
  const node = state.nodes.find((n) => n.id === selected);
  async function reload() {
    state.begin();
    const generation = useGraph.getState().generation;
    try {
      const { data, error } = await api.api.graphs({ id: DEMO_GRAPH_ID }).get();
      if (error || !data || !("document" in data))
        throw new Error("Could not load the map.");
      if (useGraph.getState().generation !== generation)
        return state.fail(
          "The draft changed while loading. Reload again when ready.",
        );
      useGraph.getState().load(data);
      select(undefined);
    } catch {
      state.fail(
        "Could not load the map. Check the server and database connection.",
      );
    } finally {
      useGraph.setState({ busy: false });
    }
  }
  React.useEffect(() => {
    void reload();
  }, []);
  async function save() {
    const { saved, generation } = useGraph.getState();
    if (!saved) return;
    const document = documentFromState();
    state.begin();
    try {
      const { data, error } = await api.api
        .graphs({ id: saved.id })
        .put({ baseRevision: saved.revision, document });
      if (error) {
        const message =
          typeof error.value === "object" &&
          error.value &&
          "message" in error.value
            ? String(error.value.message)
            : "Save failed.";
        return state.fail(message, error.status === 409);
      }
      if (data && "document" in data) state.finish(data, generation);
    } catch {
      state.fail("Could not reach the server. Your draft is still here.");
    }
  }
  async function layout() {
    state.begin();
    const startGeneration = useGraph.getState().generation;
    try {
      const { default: ELK } = await import("elkjs/lib/elk.bundled.js");
      const elk = new ELK();
      const graph = await elk.layout({
        id: "root",
        layoutOptions: {
          "elk.algorithm": "layered",
          "elk.direction": "RIGHT",
          "elk.spacing.nodeNode": "70",
          "elk.layered.spacing.nodeNodeBetweenLayers": "100",
        },
        children: state.nodes.map((n) => ({
          id: n.id,
          width: 200,
          height: 104,
        })),
        edges: state.edges.map((e) => ({
          id: e.id,
          sources: [e.source],
          targets: [e.target],
        })),
      });
      if (useGraph.getState().generation !== startGeneration)
        return state.fail("The map changed during layout. Run layout again.");
      state.layout(
        new Map(
          (graph.children ?? []).map((n) => [
            n.id,
            { x: n.x ?? 0, y: n.y ?? 0 },
          ]),
        ),
      );
      requestAnimationFrame(() => {
        void flow?.fitView({ padding: 0.25 });
      });
    } catch {
      state.fail(
        "Automatic layout could not finish. You can still drag services.",
      );
    } finally {
      useGraph.setState({ busy: false });
    }
  }
  const status = state.conflict
    ? "Save conflict"
    : state.dirty
      ? "Unsaved changes"
      : "Saved";
  return (
    <div className="shell">
      <header>
        <div className="brand">
          <span className="brand-mark">↗</span>
          <div>
            <strong>Service atlas</strong>
            <small>Architecture, kept in view</small>
          </div>
        </div>
        <div className="header-meta">
          <span className="local-dot" />
          Trusted local demo
        </div>
      </header>
      <main>
        <section className="intro">
          <div>
            <div className="eyebrow">YOUR SERVICE MAP</div>
            <h1>{state.saved?.title ?? "Storefront architecture"}</h1>
            <p>
              Map the services behind a request. Save a revision your team can
              return to.
            </p>
          </div>
          <div className="revision">
            <span>COMMITTED REVISION</span>
            <strong data-testid="revision">
              {state.saved
                ? String(state.saved.revision).padStart(2, "0")
                : "—"}
            </strong>
          </div>
        </section>
        <div className="toolbar">
          <div className="add-tools">
            <select
              aria-label="Service type"
              value={kind}
              onChange={(e) => setKind(e.target.value as ServiceKind)}
            >
              {kinds.map((k) => (
                <option key={k} value={k}>
                  {k[0].toUpperCase() + k.slice(1)} service
                </option>
              ))}
            </select>
            <button
              onClick={() => state.add(kind)}
              disabled={state.busy || !state.saved}
            >
              + Add service
            </button>
          </div>
          <div className="actions">
            <button
              onClick={() => void layout()}
              disabled={state.busy || !state.saved}
            >
              Auto layout
            </button>
            <span
              className={"save-state " + (state.dirty ? "dirty" : "")}
              data-testid="save-state"
            >
              {status}
            </span>
            <button
              className="primary"
              onClick={() => void save()}
              disabled={state.busy || !state.dirty || state.conflict}
            >
              Save revision
            </button>
          </div>
        </div>
        {state.message && (
          <div
            role="status"
            className={"notice " + (state.conflict ? "conflict" : "")}
          >
            {state.message}
            {state.conflict && (
              <button
                onClick={() => {
                  if (
                    window.confirm(
                      "Discard your local draft and load the saved revision?",
                    )
                  )
                    void reload();
                }}
              >
                Reload saved revision
              </button>
            )}
          </div>
        )}
        <div className="workspace">
          <div className="canvas">
            <ReactFlow<ServiceNode, ServiceEdge>
              nodes={state.nodes}
              edges={state.edges}
              nodeTypes={nodeTypes}
              onInit={setFlow}
              onNodesChange={state.nodeChanges}
              onEdgesChange={state.edgeChanges}
              onConnect={state.connect}
              onNodeClick={(_, n) => select(n.id)}
              onPaneClick={() => select(undefined)}
              fitView
              minZoom={0.2}
              maxZoom={2}
              defaultEdgeOptions={{
                type: "smoothstep",
                markerEnd: { type: MarkerType.ArrowClosed, color: "#758897" },
                style: { stroke: "#758897", strokeWidth: 2 },
              }}
              deleteKeyCode={["Backspace", "Delete"]}
            >
              <Background color="#d3dce0" gap={24} />
              <Controls />
            </ReactFlow>
            <div className="canvas-caption">
              Drag to arrange · Connect right handle to left handle
            </div>
          </div>
          <aside>
            <div className="eyebrow">MAP DETAILS</div>
            <h2>{node ? "Edit service" : "A clear path through the stack"}</h2>
            {node ? (
              <>
                <label htmlFor="service-name">Service name</label>
                <input
                  id="service-name"
                  aria-label="Service name"
                  maxLength={60}
                  value={node.data.label}
                  onChange={(e) => state.rename(node.id, e.target.value)}
                />
                <div className="detail-kind">{node.data.kind} service</div>
                <button
                  className="danger"
                  onClick={() => {
                    state.remove(node.id);
                    select(undefined);
                  }}
                >
                  Remove service
                </button>
                <p>
                  Removing a service also removes its connections. Save to
                  commit the change.
                </p>
              </>
            ) : (
              <>
                <p>
                  Choose a service to rename it, or add a new part of your
                  architecture.
                </p>
                <div className="counts">
                  <div>
                    <strong>{state.nodes.length}</strong>
                    <span>services</span>
                  </div>
                  <div>
                    <strong>{state.edges.length}</strong>
                    <span>connections</span>
                  </div>
                </div>
                <div className="legend">
                  {kinds.map((k) => (
                    <div key={k}>
                      <span className={"swatch " + k} />
                      {k}
                    </div>
                  ))}
                </div>
                <p>
                  One connection per direction. Self connections are not
                  allowed. Up to 100 services and 200 connections.
                </p>
              </>
            )}
            <div className="storage-note">
              <strong>Remembered in Postgres</strong>
              <p>
                Every save commits the map and its revision together. A stale
                tab must reload before saving.
              </p>
            </div>
            <button
              className="reload"
              disabled={state.busy}
              onClick={() => {
                if (
                  !state.dirty ||
                  window.confirm("Discard your local draft and reload?")
                )
                  void reload();
              }}
            >
              Reload map
            </button>
          </aside>
        </div>
      </main>
      <footer>
        <span>React Flow · Zustand · ELK · Elysia + Eden · Drizzle</span>
        <span>ClickHouse Managed Postgres</span>
      </footer>
    </div>
  );
}
createRoot(document.getElementById("root")!).render(<App />);
