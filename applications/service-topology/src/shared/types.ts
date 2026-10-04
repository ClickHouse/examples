export type ServiceKind = "web" | "api" | "worker" | "database";
export type ServiceNode = {
  id: string;
  type: "service";
  position: { x: number; y: number };
  data: { label: string; kind: ServiceKind };
};
export type ServiceEdge = { id: string; source: string; target: string };
export type GraphDocument = { nodes: ServiceNode[]; edges: ServiceEdge[] };
export type SavedGraph = {
  id: string;
  title: string;
  revision: number;
  document: GraphDocument;
  updatedAt: string;
};
export const DEMO_GRAPH_ID = "67bc2cf0-5b0f-45c8-bf6a-7b4bb5155a50";
