import { describe, expect, test } from "bun:test";
import { graphProblem } from "../src/server/graph";
import type { GraphDocument } from "../src/shared/types";
const first = "11111111-1111-4111-8111-111111111111";
const second = "22222222-2222-4222-8222-222222222222";
const document = (): GraphDocument => ({
  nodes: [first, second].map((id) => ({
    id,
    type: "service",
    position: { x: 1, y: 2 },
    data: { label: "API", kind: "api" },
  })),
  edges: [],
});
describe("graph meaning", () => {
  test("allows cycles between distinct services", () => {
    const d = document();
    d.edges = [
      { id: crypto.randomUUID(), source: first, target: second },
      { id: crypto.randomUUID(), source: second, target: first },
    ];
    expect(graphProblem(d)).toBeUndefined();
  });
  test("rejects dangling connections", () => {
    const d = document();
    d.edges = [
      { id: crypto.randomUUID(), source: first, target: crypto.randomUUID() },
    ];
    expect(graphProblem(d)).toContain("existing");
  });
  test("rejects repeated nodes and blank names", () => {
    const d = document();
    d.nodes.push(d.nodes[0]);
    expect(graphProblem(d)).toContain("unique");
    d.nodes.pop();
    d.nodes[0].data.label = "  ";
    expect(graphProblem(d)).toContain("blank");
  });
  test("rejects self connections and duplicates", () => {
    const d = document();
    d.edges = [{ id: crypto.randomUUID(), source: first, target: first }];
    expect(graphProblem(d)).toContain("itself");
    d.edges = [
      { id: crypto.randomUUID(), source: first, target: second },
      { id: crypto.randomUUID(), source: first, target: second },
    ];
    expect(graphProblem(d)).toContain("one connection");
  });
  test("rejects non-finite coordinates", () => {
    const d = document();
    d.nodes[0].position.x = Infinity;
    expect(graphProblem(d)).toContain("finite");
  });
});
