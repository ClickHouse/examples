import test from "node:test";
import assert from "node:assert/strict";
import { lookup } from "node:dns/promises";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFileSync } from "node:child_process";
import { Pool } from "pg";
import { database, databaseConfig, closeDatabase } from "../server/database";
import {
  assign,
  bootstrap,
  viewportJobs,
  saveMap,
  DispatchError,
} from "../server/dispatch";
const id = (prefix: string, suffix: number) =>
  `${prefix}0000000-0000-4000-8000-${String(suffix).padStart(12, "0")}`;
test("managed PostGIS: indexed viewport, stored coverage, revision races, grants and verified TLS", async () => {
  try {
    const identity = (
      await database().query(
        "SELECT current_user,version() AS version,public.postgis_full_version() AS postgis",
      )
    ).rows[0];
    assert.equal(identity.current_user, "dispatch_app");
    console.log(JSON.stringify(identity));
    const limited = await viewportJobs({
      west: -1.485,
      south: 53.355,
      east: -1.475,
      north: 53.365,
    });
    assert.ok(limited.jobs.some((job) => job.code === "FD-001"));
    assert.ok(
      limited.jobs.every(
        (job) =>
          job.position[0] >= -1.485 &&
          job.position[0] <= -1.475 &&
          job.position[1] >= 53.355 &&
          job.position[1] <= 53.365,
      ),
    );
    const river = (
      await database().query(
        "SELECT team_id,revision FROM dispatch.jobs WHERE id=$1",
        [id("4", 2)],
      )
    ).rows[0];
    await assert.rejects(
      assign({
        jobId: id("4", 2),
        teamId: id("3", 1),
        revision: river.revision,
      }),
      (error) => error instanceof DispatchError && error.status === 400,
    );
    assert.deepEqual(
      (
        await database().query(
          "SELECT team_id,revision FROM dispatch.jobs WHERE id=$1",
          [id("4", 2)],
        )
      ).rows[0],
      river,
    );
    const revision = (
      await database().query("SELECT revision FROM dispatch.jobs WHERE id=$1", [
        id("4", 4),
      ])
    ).rows[0].revision;
    const race = await Promise.allSettled([
      assign({ jobId: id("4", 4), teamId: id("3", 1), revision }),
      assign({ jobId: id("4", 4), teamId: id("3", 3), revision }),
    ]);
    assert.equal(
      race.filter((result) => result.status === "fulfilled").length,
      1,
    );
    assert.ok(
      race.some(
        (result) =>
          result.status === "rejected" &&
          result.reason instanceof DispatchError &&
          result.reason.status === 409,
      ),
    );
    const state = (await bootstrap()).state;
    const saves = await Promise.allSettled([
      saveMap({ ...state, mode: "priority" }),
      saveMap({ ...state, mode: "assignments" }),
    ]);
    assert.equal(
      saves.filter((result) => result.status === "fulfilled").length,
      1,
    );
    assert.ok(
      saves.some(
        (result) =>
          result.status === "rejected" &&
          result.reason instanceof DispatchError &&
          result.reason.status === 409,
      ),
    );
    for (const sql of [
      "CREATE TABLE dispatch.forbidden(id integer)",
      "ALTER TABLE dispatch.jobs ADD COLUMN forbidden text",
      "DELETE FROM dispatch.jobs",
      "UPDATE dispatch.jobs SET geom=public.ST_SetSRID(public.ST_MakePoint(0,0),4326)",
      "INSERT INTO dispatch.jobs(id,code,title,priority,geom) VALUES(gen_random_uuid(),'forbidden','Forbidden','routine',public.ST_SetSRID(public.ST_MakePoint(0,0),4326))",
    ])
      await assert.rejects(
        database().query(sql),
        (error: any) => error.code === "42501",
      );
    const config = databaseConfig();
    const ip = new URL(process.env.DATABASE_URL!);
    ip.hostname = (await lookup(ip.hostname, { family: 4 })).address;
    const wrongName = new Pool({
      ...config,
      connectionString: ip.toString(),
      max: 1,
      ssl: { ...(config.ssl as object), servername: "wrong-host.invalid" },
    });
    try {
      await assert.rejects(
        wrongName.query("SELECT 1"),
        (err: any) => err.code === "ERR_TLS_CERT_ALTNAME_INVALID",
      );
    } finally {
      await wrongName.end();
    }
    const directory = mkdtempSync(join(tmpdir(), "dispatch-ca-"));
    try {
      execFileSync(
        "openssl",
        [
          "req",
          "-x509",
          "-newkey",
          "rsa:2048",
          "-nodes",
          "-keyout",
          join(directory, "key.pem"),
          "-out",
          join(directory, "ca.pem"),
          "-days",
          "1",
          "-subj",
          "/CN=unrelated-dispatch-root",
        ],
        { stdio: "ignore" },
      );
      const wrongCa = new Pool({
        ...config,
        max: 1,
        ssl: {
          ...(config.ssl as object),
          ca: readFileSync(join(directory, "ca.pem"), "utf8"),
        },
      });
      try {
        await assert.rejects(wrongCa.query("SELECT 1"), (err: any) =>
          [
            "UNABLE_TO_VERIFY_LEAF_SIGNATURE",
            "UNABLE_TO_GET_ISSUER_CERT_LOCALLY",
            "SELF_SIGNED_CERT_IN_CHAIN",
            "DEPTH_ZERO_SELF_SIGNED_CERT",
          ].includes(err.code),
        );
      } finally {
        await wrongCa.end();
      }
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
    console.log(
      "Passed PostGIS viewport, outside-area rollback, competing job/map writers, restricted grants and pg wrong-CA/hostname controls.",
    );
  } finally {
    await closeDatabase();
  }
});
