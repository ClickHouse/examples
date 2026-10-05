import type { IncomingMessage, ServerResponse } from "node:http";
import { grafast } from "postgraphile/grafast";
import { createGraphile, verifiedSessions } from "../src/server/preset.ts";
import { test, after } from "node:test";
import assert from "node:assert/strict";
import { connectDatabase } from "../src/server/database.ts";
const origin = process.env.APP_ORIGIN ?? "http://127.0.0.1:3002";
const A = "10000000-0000-4000-8000-000000000001",
  B = "10000000-0000-4000-8000-000000000002";
const AP = "20000000-0000-4000-8000-000000000001",
  BP = "20000000-0000-4000-8000-000000000003";
const pagination = "20000000-0000-4000-8000-000000000010";
const pool = await connectDatabase();
after(() => pool.end());
async function login(email: string, password: string) {
  const r = await fetch(origin + "/api/login", {
    method: "POST",
    headers: { Origin: origin, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  assert.equal(r.status, 200);
  return r.headers.get("set-cookie")!.split(";")[0]!;
}
const alice = await login("alice@example.test", "river-demo"),
  bob = await login("bob@example.test", "summit-demo");
async function gql(
  cookie: string,
  query: string,
  variables: Record<string, unknown> = {},
  headers: Record<string, string> = {},
) {
  const r = await fetch(origin + "/graphql", {
    method: "POST",
    headers: {
      Origin: origin,
      Cookie: cookie,
      "Content-Type": "application/json",
      ...headers,
    },
    body: JSON.stringify({ query, variables }),
  });
  return { status: r.status, body: await r.json() };
}
async function scoped(
  workspace: string,
  action: (client: import("pg").PoolClient) => Promise<void>,
) {
  const c = await pool.connect();
  try {
    await c.query("BEGIN");
    await c.query("SET LOCAL ROLE tracker_member");
    await c.query("SELECT set_config('app.workspace_id',$1,true)", [workspace]);
    await action(c);
    await c.query("COMMIT");
  } catch (e) {
    await c.query("ROLLBACK");
    throw e;
  } finally {
    c.release();
  }
}
test("all effective member RLS policies, transaction-local context and privilege denials", async () => {
  await scoped(A, async (c) => {
    for (const table of ["workspaces", "projects", "tasks"]) {
      const r = await c.query(`SELECT * FROM tracker.${table}`);
      assert.ok(r.rows.length > 0);
      assert.ok(r.rows.every((row) => (row.workspace_id ?? row.id) === A));
    }
    assert.equal(
      (await c.query("SELECT current_user AS role")).rows[0].role,
      "tracker_member",
    );
  });
  const c = await pool.connect();
  try {
    const state = await c.query(
      "SELECT current_user AS role,current_setting('app.workspace_id',true) AS workspace",
    );
    assert.equal(state.rows[0].role, "tracker_api");
    assert.ok(!state.rows[0].workspace);
    await assert.rejects(c.query("SELECT * FROM tracker.projects"), {
      code: "42501",
    });
    for (const sql of [
      "SELECT * FROM tracker_private.accounts",
      "SELECT * FROM tracker_private.sessions",
      "CREATE TABLE tracker.intruder(id int)",
      "CREATE SCHEMA intruder",
      "SET ROLE tracker_migration",
    ]) {
      await c.query("BEGIN");
      await c.query("SET LOCAL ROLE tracker_member");
      await assert.rejects(c.query(sql), { code: "42501" });
      await c.query("ROLLBACK");
    }
  } finally {
    c.release();
  }
});
test("actual Grafast execution resets role and workspace settings on its own pooled connections", async () => {
  const graphile = createGraphile(pool);
  try {
    const { schema, resolvedPreset } = await graphile.getSchemaResult();
    for (const workspace of [A, B, A]) {
      const req = {} as IncomingMessage;
      verifiedSessions.set(req, {
        userId: "test",
        email: "test@example.test",
        workspaceId: workspace,
        workspaceName: "test",
      });
      const result = await grafast({
        schema,
        resolvedPreset,
        requestContext: { node: { req, res: {} as ServerResponse } },
        source: "{allWorkspaces(first:10){nodes{rowId}}}",
      });
      assert.ok(!(Symbol.asyncIterator in result));
      assert.equal(result.errors, undefined);
      assert.deepEqual(
        (result.data as any).allWorkspaces.nodes.map((w: any) => w.rowId),
        [workspace],
      );
    }
    const clients = await Promise.all(
      Array.from({ length: pool.totalCount }, () => pool.connect()),
    );
    try {
      for (const c of clients) {
        const state = (
          await c.query(
            "SELECT current_user AS role,current_setting('app.workspace_id',true) AS workspace",
          )
        ).rows[0];
        assert.equal(state.role, "tracker_api");
        assert.ok(!state.workspace);
      }
    } finally {
      clients.forEach((c) => c.release());
    }
  } finally {
    await graphile.release();
  }
});
test("verified sessions isolate generated nested relations and ignore forged tenant headers", async () => {
  const query =
    "{ allWorkspaces(first:10){nodes{rowId name}} allProjects(first:50){nodes{rowId workspaceId tasksByProjectIdAndWorkspaceId(first:50){nodes{workspaceId title}} workspaceByWorkspaceId{rowId}}} }";
  for (const [cookie, workspace] of [
    [alice, A],
    [bob, B],
  ]) {
    const { body, status } = await gql(
      cookie!,
      query,
      {},
      {
        "X-Workspace-Id": workspace === A ? B : A,
        "X-Pg-Settings": JSON.stringify({
          role: "tracker_migration",
          "app.workspace_id": B,
        }),
      },
    );
    assert.equal(status, 200);
    assert.equal(body.errors, undefined);
    assert.deepEqual(
      body.data.allWorkspaces.nodes.map((r: any) => r.rowId),
      [workspace],
    );
    assert.ok(
      body.data.allProjects.nodes.every(
        (p: any) =>
          p.workspaceId === workspace &&
          p.workspaceByWorkspaceId.rowId === workspace &&
          p.tasksByProjectIdAndWorkspaceId.nodes.every(
            (t: any) => t.workspaceId === workspace,
          ),
      ),
    );
  }
  const other = await gql(
    alice,
    "query($id:UUID!){projectByRowId(rowId:$id){rowId tasksByProjectIdAndWorkspaceId(first:10){nodes{title}}}}",
    { id: BP },
  );
  assert.equal(other.body.data.projectByRowId, null);
  const forged = await gql(
    "ground_session=" + "0".repeat(64),
    "{allProjects(first:1){nodes{rowId}}}",
  );
  assert.equal(forged.status, 401);
});
test("actual HTTP mutations enforce workspace checks and composite foreign keys", async () => {
  const mutation =
    'mutation($project:UUID!,$workspace:UUID!){createTask(input:{task:{projectId:$project,workspaceId:$workspace,title:"Must never appear"}}){task{rowId}}}';
  for (const [project, workspace] of [
    [AP, B],
    [BP, A],
  ]) {
    const result = await gql(alice, mutation, { project, workspace });
    assert.ok(result.body.errors?.length);
    assert.equal(result.body.data.createTask, null);
  }
  await scoped(A, async (c) =>
    assert.equal(
      (
        await c.query(
          "SELECT count(*)::int AS n FROM tracker.tasks WHERE title='Must never appear'",
        )
      ).rows[0].n,
      0,
    ),
  );
  const result = await gql(
    alice,
    'mutation{createProject(input:{project:{name:"HTTP saved project",description:"Persisted through generated mutation"}}){project{rowId workspaceId}}}',
  );
  assert.equal(result.body.errors, undefined);
  assert.equal(result.body.data.createProject.project.workspaceId, A);
  const id = result.body.data.createProject.project.rowId;
  const read = await gql(
    alice,
    "query($id:UUID!){projectByRowId(rowId:$id){name}}",
    { id },
  );
  assert.equal(read.body.data.projectByRowId.name, "HTTP saved project");
});
test("a generated cross-workspace UPDATE cannot change the other team's stored task", async () => {
  const task = "30000000-0000-4000-8000-000000000004";
  const query = "query($id:UUID!){taskByRowId(rowId:$id){rowId done}}";
  const before = (await gql(bob, query, { id: task })).body.data.taskByRowId;
  assert.ok(before);
  const mutation =
    "mutation($id:UUID!,$done:Boolean!){updateTaskByRowId(input:{rowId:$id,taskPatch:{done:$done}}){task{rowId done}}}";
  const result = await gql(alice, mutation, { id: task, done: !before.done });
  assert.ok(
    result.body.errors?.length ||
      result.body.data.updateTaskByRowId === null ||
      result.body.data.updateTaskByRowId?.task === null,
  );
  const after = (await gql(bob, query, { id: task })).body.data.taskByRowId;
  assert.deepEqual(after, before);
});
test("fragment pagination limits and request boundary controls operate over HTTP", async () => {
  for (const query of [
    "{allProjects{...Rows}} fragment Rows on ProjectConnection{nodes{rowId}}",
    "{allProjects{... on ProjectConnection{nodes{rowId}}}}",
    "{__schema{queryType{name}}}",
  ]) {
    assert.equal((await gql(alice, query)).status, 400);
  }
  const denied = await fetch(origin + "/graphql", {
    method: "POST",
    headers: {
      Origin: "http://foreign.test",
      Cookie: alice,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ query: "{allProjects(first:1){nodes{rowId}}}" }),
  });
  assert.equal(denied.status, 403);
  const tooLarge = await gql(alice, " ".repeat(9000));
  assert.equal(tooLarge.status, 400);
});
test("generated cursor pagination covers more than20projects and50tasks", async () => {
  await scoped(A, async (c) => {
    await c.query(
      "INSERT INTO tracker.projects(id,name,created_at) VALUES($1,'Pagination notebook',now()+interval '1 minute') ON CONFLICT(id) DO NOTHING",
      [pagination],
    );
    await c.query(
      "INSERT INTO tracker.projects(id,name) SELECT ('21000000-0000-4000-8000-'||lpad(g::text,12,'0'))::uuid,'Pagination project '||g FROM generate_series(1,21) g ON CONFLICT(id) DO NOTHING",
    );
    await c.query(
      "INSERT INTO tracker.tasks(id,project_id,title,created_at) SELECT ('31000000-0000-4000-8000-'||lpad(g::text,12,'0'))::uuid,$1,'Pagination step '||lpad(g::text,2,'0'),now()-g*interval '1 second' FROM generate_series(1,51)g ON CONFLICT(id) DO NOTHING",
      [pagination],
    );
  });
  const q =
    "query($after:Cursor){allProjects(first:20,after:$after,orderBy:[CREATED_AT_DESC,PRIMARY_KEY_DESC]){totalCount pageInfo{hasNextPage endCursor} nodes{rowId}}}";
  const response = await gql(alice, q);
  assert.equal(response.status, 200, JSON.stringify(response.body));
  assert.equal(response.body.errors, undefined, JSON.stringify(response.body));
  const first = response.body.data.allProjects;
  assert.ok(first.totalCount > 20);
  assert.equal(first.nodes.length, 20);
  assert.equal(first.pageInfo.hasNextPage, true);
  const second = (await gql(alice, q, { after: first.pageInfo.endCursor })).body
    .data.allProjects;
  assert.equal(
    new Set([...first.nodes, ...second.nodes].map((p: any) => p.rowId)).size,
    first.totalCount,
  );
  const tq =
    "query($id:UUID!,$after:Cursor){projectByRowId(rowId:$id){tasksByProjectIdAndWorkspaceId(first:50,after:$after,orderBy:[CREATED_AT_DESC,PRIMARY_KEY_DESC]){totalCount pageInfo{hasNextPage endCursor} nodes{rowId}}}}";
  const tasks = (await gql(alice, tq, { id: pagination })).body.data
    .projectByRowId.tasksByProjectIdAndWorkspaceId;
  assert.equal(tasks.totalCount, 51);
  assert.equal(tasks.nodes.length, 50);
  const next = (
    await gql(alice, tq, { id: pagination, after: tasks.pageInfo.endCursor })
  ).body.data.projectByRowId.tasksByProjectIdAndWorkspaceId;
  assert.equal(next.nodes.length, 1);
  assert.equal(next.pageInfo.hasNextPage, false);
  assert.ok(!tasks.nodes.some((t: any) => t.rowId === next.nodes[0].rowId));
});
