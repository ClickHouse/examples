import test from "node:test";
import { get } from "node:http";
import assert from "node:assert/strict";
import { PMTiles } from "pmtiles";
import { createApplication } from "../server/http";
import {
  assignmentSchema,
  mapStateSchema,
  viewportSchema,
} from "../src/domain";

test("the checked-in PMTiles archive is read through actual HTTP byte ranges", async () => {
  process.env.APP_ORIGIN = "http://127.0.0.1:3002";
  const server = createApplication();
  await new Promise<void>((resolve) =>
    server.listen(3002, "127.0.0.1", resolve),
  );
  try {
    const url = `${process.env.APP_ORIGIN}/maintenance-town.pmtiles`;
    const response = await fetch(url, { headers: { range: "bytes=0-126" } });
    assert.equal(response.status, 206);
    assert.equal(response.headers.get("content-range"), "bytes 0-126/7995");
    assert.equal((await response.arrayBuffer()).byteLength, 127);
    const archive = new PMTiles(url);
    const header = await archive.getHeader();
    assert.equal(header.specVersion, 3);
    assert.equal(header.numAddressedTiles, 61);
    assert.equal(header.minZoom, 12);
    const metadata = await archive.getMetadata();
    assert.equal(
      (metadata as { vector_layers: unknown[] }).vector_layers.length,
      3,
    );
    const tile = await archive.getZxy(12, 2031, 1327);
    assert.ok(tile && tile.data.byteLength > 0);
    for (const range of ["bytes=-10", "bytes=8000-", "bytes=0-1,3-5"]) {
      assert.equal((await fetch(url, { headers: { range } })).status, 416);
    }
    const wrongHost = await new Promise<number | undefined>((resolve) =>
      get(url, { headers: { host: "unexpected.example" } }, (response) => {
        response.resume();
        resolve(response.statusCode);
      }),
    );
    assert.equal(wrongHost, 403);
  } finally {
    await new Promise<void>((resolve, reject) =>
      server.close((error) => (error ? reject(error) : resolve())),
    );
  }
});

test("public payloads reject world viewports and non-incrementable PostgreSQL revisions", () => {
  assert.equal(
    viewportSchema.safeParse({ west: -180, south: -90, east: 180, north: 90 })
      .success,
    false,
  );
  const ids = {
    jobId: "40000000-0000-4000-8000-000000000001",
    teamId: "30000000-0000-4000-8000-000000000001",
  };
  assert.equal(
    assignmentSchema.safeParse({ ...ids, revision: 2147483647 }).success,
    false,
  );
  assert.equal(
    assignmentSchema.safeParse({ ...ids, revision: 2147483646 }).success,
    true,
  );
  assert.equal(
    mapStateSchema.safeParse({
      longitude: -1.467,
      latitude: 53.373,
      zoom: 13,
      areaId: "20000000-0000-4000-8000-000000000001",
      mode: "priority",
      revision: 2147483647,
    }).success,
    false,
  );
});
