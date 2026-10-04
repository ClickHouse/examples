import { create } from "zustand";
import {
  applyEdgeChanges,
  applyNodeChanges,
  type EdgeChange,
  type NodeChange,
  type Connection,
} from "@xyflow/react";
import type {
  GraphDocument,
  SavedGraph,
  ServiceNode,
  ServiceEdge,
  ServiceKind,
} from "../shared/types";
type State = {
  saved?: SavedGraph;
  nodes: ServiceNode[];
  edges: ServiceEdge[];
  dirty: boolean;
  busy: boolean;
  message: string;
  conflict: boolean;
  generation: number;
  load: (graph: SavedGraph) => void;
  nodeChanges: (changes: NodeChange<ServiceNode>[]) => void;
  edgeChanges: (changes: EdgeChange<ServiceEdge>[]) => void;
  connect: (connection: Connection) => void;
  add: (kind: ServiceKind) => void;
  rename: (id: string, label: string) => void;
  remove: (id: string) => void;
  layout: (positions: Map<string, { x: number; y: number }>) => void;
  begin: () => void;
  finish: (graph: SavedGraph, generation: number) => void;
  fail: (message: string, conflict?: boolean) => void;
};
export const useGraph = create<State>((set, get) => ({
  nodes: [],
  edges: [],
  dirty: false,
  busy: false,
  message: "",
  conflict: false,
  generation: 0,
  load: (graph) =>
    set({
      saved: graph,
      nodes: graph.document.nodes,
      edges: graph.document.edges,
      dirty: false,
      conflict: false,
      message: "",
      generation: get().generation + 1,
    }),
  nodeChanges: (changes) => {
    const contentChange = changes.some(
      (c) => c.type !== "select" && c.type !== "dimensions",
    );
    const nodes = applyNodeChanges(changes, get().nodes);
    const ids = new Set(nodes.map((n) => n.id));
    set({
      nodes,
      edges: get().edges.filter((e) => ids.has(e.source) && ids.has(e.target)),
      ...(contentChange
        ? { dirty: true, generation: get().generation + 1 }
        : {}),
    });
  },
  edgeChanges: (changes) =>
    set({
      edges: applyEdgeChanges(changes, get().edges),
      ...(changes.some((c) => c.type !== "select")
        ? { dirty: true, generation: get().generation + 1 }
        : {}),
    }),
  connect: (c) => {
    if (!c.source || !c.target) return;
    if (c.source === c.target)
      return set({ message: "A service cannot connect to itself." });
    if (get().edges.some((e) => e.source === c.source && e.target === c.target))
      return set({ message: "That connection already exists." });
    if (get().edges.length >= 200)
      return set({ message: "This map allows up to 200 connections." });
    set({
      edges: [
        ...get().edges,
        { id: crypto.randomUUID(), source: c.source, target: c.target },
      ],
      dirty: true,
      generation: get().generation + 1,
      message: "",
    });
  },
  add: (kind) => {
    if (get().nodes.length >= 100)
      return set({ message: "This map allows up to 100 services." });
    set({
      nodes: [
        ...get().nodes,
        {
          id: crypto.randomUUID(),
          type: "service",
          position: { x: 120 + get().nodes.length * 30, y: 320 },
          data: { label: "New " + kind, kind },
        },
      ],
      dirty: true,
      generation: get().generation + 1,
    });
  },
  rename: (id, label) =>
    set({
      nodes: get().nodes.map((n) =>
        n.id === id ? { ...n, data: { ...n.data, label } } : n,
      ),
      dirty: true,
      generation: get().generation + 1,
    }),
  remove: (id) =>
    set({
      nodes: get().nodes.filter((n) => n.id !== id),
      edges: get().edges.filter((e) => e.source !== id && e.target !== id),
      dirty: true,
      generation: get().generation + 1,
    }),
  layout: (positions) =>
    set({
      nodes: get().nodes.map((n) => ({
        ...n,
        position: positions.get(n.id) ?? n.position,
      })),
      dirty: true,
      generation: get().generation + 1,
    }),
  begin: () => set({ busy: true, message: "" }),
  finish: (graph, generation) =>
    set({
      saved: graph,
      busy: false,
      conflict: false,
      dirty: get().generation !== generation,
      message:
        get().generation === generation
          ? "All changes saved."
          : "Snapshot saved. Your newer edits are still unsaved.",
    }),
  fail: (message, conflict = false) => set({ message, conflict, busy: false }),
}));
export function documentFromState(): GraphDocument {
  const { nodes, edges } = useGraph.getState();
  // React Flow keeps selection and measured dimensions locally; persist only the document.
  return {
    nodes: nodes.map(({ id, type, position, data }) => ({
      id,
      type,
      position: { ...position },
      data: { ...data },
    })),
    edges: edges.map(({ id, source, target }) => ({ id, source, target })),
  };
}
