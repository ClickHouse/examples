import {
  afterAll,
  afterEach,
  beforeAll,
  beforeEach,
  describe,
  expect,
  test,
} from "bun:test";
import { connectDatabase } from "../src/server/database";
import { createApi } from "../src/server/app";
import type { GraphDocument } from "../src/shared/types";
let runtime: Awaited<ReturnType<typeof connectDatabase>>;
let admin: Awaited<ReturnType<typeof connectDatabase>>;
let id: string;
const doc: GraphDocument = {
  nodes: [
    {
      id: "11111111-1111-4111-8111-111111111111",
      type: "service",
      position: { x: 10, y: 20 },
      data: { label: "Test API", kind: "api" },
    },
  ],
  edges: [],
};
beforeAll(async () => {
  if (!process.env.DATABASE_TEST_ADMIN_URL)
    throw new Error(
      "Set DATABASE_TEST_ADMIN_URL to the migration login for a dedicated test database.",
    );
  runtime = await connectDatabase();
  admin = await connectDatabase(process.env.DATABASE_TEST_ADMIN_URL);
});
beforeEach(async () => {
  id = crypto.randomUUID();
  await admin.client.begin(async (tx) => {
    await tx`SET LOCAL ROLE topology_owner`;
    await tx`INSERT INTO service_topology.graphs(id,title,revision,document) VALUES (${id},'Test',1,${doc}::jsonb)`;
    await tx`INSERT INTO service_topology.revisions(graph_id,revision,document) VALUES (${id},1,${doc}::jsonb)`;
  });
});
afterEach(async () => {
  await admin.client.begin(async (tx) => {
    await tx`SET LOCAL ROLE topology_owner`;
    await tx`DELETE FROM service_topology.graphs WHERE id=${id}`;
  });
});
afterAll(async () => {
  await runtime?.client.close();
  await admin?.client.close();
});
function request(body: unknown) {
  return createApi(runtime.db).handle(
    new Request("http://127.0.0.1:3000/api/graphs/" + id, {
      method: "PUT",
      headers: {
        "content-type": "application/json",
        origin: "http://127.0.0.1:3000",
      },
      body: JSON.stringify(body),
    }),
  );
}
describe("real Postgres saves", () => {
  test("sixteen concurrent edits commit one revision", async () => {
    const replies = await Promise.all(
      Array.from({ length: 16 }, () =>
        request({ baseRevision: 1, document: doc }),
      ),
    );
    expect(replies.filter((r) => r.status === 200)).toHaveLength(1);
    expect(replies.filter((r) => r.status === 409)).toHaveLength(15);
    const row =
      await runtime.client`SELECT revision,document,jsonb_typeof(document) AS document_type FROM service_topology.graphs WHERE id=${id}`;
    expect(row[0].revision).toBe(2);
    expect(row[0].document_type).toBe("object");
    expect(row[0].document).toEqual(doc);
    const count =
      await runtime.client`SELECT count(*)::int AS total FROM service_topology.revisions WHERE graph_id=${id}`;
    expect(count[0].total).toBe(2);
  });
  test("snapshot failure rolls current graph back", async () => {
    await admin.client.begin(async (tx) => {
      await tx`SET LOCAL ROLE topology_owner`;
      await tx`INSERT INTO service_topology.revisions(graph_id,revision,document) VALUES(${id},2,${doc}::jsonb)`;
    });
    const changed = structuredClone(doc);
    changed.nodes[0].data.label = "Should roll back";
    expect((await request({ baseRevision: 1, document: changed })).status).toBe(
      500,
    );
    const rows =
      await runtime.client`SELECT revision,document,jsonb_typeof(document) AS document_type FROM service_topology.graphs WHERE id=${id}`;
    expect(rows[0].revision).toBe(1);
    expect(rows[0].document).toEqual(doc);
  });
  test("rejects malformed and semantically invalid graph before storage", async () => {
    expect(
      (
        await request({
          baseRevision: 1,
          document: { nodes: [{ bad: "shape" }], edges: [] },
        })
      ).status,
    ).toBe(422);
    const invalid = structuredClone(doc);
    invalid.edges = [
      {
        id: crypto.randomUUID(),
        source: doc.nodes[0].id,
        target: crypto.randomUUID(),
      },
    ];
    expect((await request({ baseRevision: 1, document: invalid })).status).toBe(
      400,
    );
    const duplicate = structuredClone(doc);
    duplicate.nodes.push(duplicate.nodes[0]);
    expect(
      (await request({ baseRevision: 1, document: duplicate })).status,
    ).toBe(400);
    const huge = structuredClone(doc);
    huge.nodes = Array.from({ length: 101 }, () => ({
      ...doc.nodes[0],
      id: crypto.randomUUID(),
    }));
    expect((await request({ baseRevision: 1, document: huge })).status).toBe(
      422,
    );
    const rows =
      await runtime.client`SELECT revision FROM service_topology.graphs WHERE id=${id}`;
    expect(rows[0].revision).toBe(1);
  });
  test("database requires both graph arrays and rejects untrusted requests", async () => {
    await expect(
      Promise.resolve(
        runtime.client`UPDATE service_topology.graphs SET document=${{ nodes: [] }}::jsonb WHERE id=${id}`,
      ),
    ).rejects.toThrow();
    await expect(
      Promise.resolve(
        runtime.client`UPDATE service_topology.graphs SET document=${{ nodes: null, edges: [] }}::jsonb WHERE id=${id}`,
      ),
    ).rejects.toThrow();
    const api = createApi(runtime.db);
    expect(
      (
        await api.handle(
          new Request("http://untrusted.example:3000/api/graphs/" + id),
        )
      ).status,
    ).toBe(403);
    expect(
      (
        await api.handle(
          new Request("http://127.0.0.1:3000/api/graphs/" + id, {
            method: "PUT",
            headers: {
              origin: "http://untrusted.example",
              "content-type": "application/json",
            },
            body: JSON.stringify({ baseRevision: 1, document: doc }),
          }),
        )
      ).status,
    ).toBe(403);
  });
  test("runtime role cannot change schema or overwrite snapshots", async () => {
    await expect(
      Promise.resolve(
        runtime.client`CREATE TABLE service_topology.forbidden(id int)`,
      ),
    ).rejects.toThrow();
    await expect(
      Promise.resolve(
        runtime.client`UPDATE service_topology.revisions SET document='{}' WHERE graph_id=${id}`,
      ),
    ).rejects.toThrow();
    await expect(
      Promise.resolve(
        runtime.client`DELETE FROM service_topology.revisions WHERE graph_id=${id}`,
      ),
    ).rejects.toThrow();
    await expect(
      Promise.resolve(
        runtime.client`UPDATE service_topology.graphs SET title='Other' WHERE id=${id}`,
      ),
    ).rejects.toThrow();
  });
});
