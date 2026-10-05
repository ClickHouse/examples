import type { PoolClient } from "pg";
import { database } from "./database";
import {
  assignmentSchema,
  mapStateSchema,
  viewportSchema,
  type Area,
  type Bootstrap,
  type Job,
  type MapState,
  type Team,
  type Viewport,
} from "../src/domain";

export class DispatchError extends Error {
  constructor(
    message: string,
    public status = 400,
  ) {
    super(message);
  }
}
async function transaction<T>(work: (client: PoolClient) => Promise<T>) {
  const client = await database().connect();
  try {
    await client.query("BEGIN");
    const result = await work(client);
    await client.query("COMMIT");
    return result;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}
export async function bootstrap(): Promise<Bootstrap> {
  return transaction(async (client) => {
    await client.query(
      "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY",
    );
    const areas = (
      await client.query<Area>(`
      SELECT id, name, color, jsonb_build_object(
        'type','Feature','properties',jsonb_build_object('id',id,'name',name),
        'geometry',public.ST_AsGeoJSON(boundary)::jsonb) AS feature
      FROM dispatch.areas ORDER BY name
    `)
    ).rows;
    const teams = (
      await client.query<Team>(`
      SELECT id,name,area_id AS "areaId",
        jsonb_build_array(public.ST_X(depot),public.ST_Y(depot)) AS position
      FROM dispatch.teams ORDER BY name
    `)
    ).rows;
    const state = (
      await client.query<MapState>(`
      SELECT longitude,latitude,zoom,area_id AS "areaId",mode,revision
      FROM dispatch.map_state WHERE id='dispatch'
    `)
    ).rows[0];
    return { areas, teams, state };
  });
}
export async function viewportJobs(input: unknown) {
  const bounds = viewportSchema.parse(input);
  const rows = (
    await database().query<Job & { total: number }>(
      `
    SELECT id,code,title,priority,team_id AS "teamId",revision,
      jsonb_build_array(public.ST_X(geom),public.ST_Y(geom)) AS position,
      (count(*) OVER ())::integer AS total
    FROM dispatch.jobs
    WHERE public.ST_Intersects(geom,public.ST_MakeEnvelope($1,$2,$3,$4,4326))
    ORDER BY CASE priority WHEN 'urgent' THEN 0 ELSE 1 END,code LIMIT 100
  `,
      [bounds.west, bounds.south, bounds.east, bounds.north],
    )
  ).rows;
  const total = rows[0]?.total ?? 0;
  return {
    jobs: rows.map(({ total: _total, ...job }) => job),
    total,
    capped: total > rows.length,
  };
}
export async function assign(input: {
  jobId: string;
  teamId: string;
  revision: number;
}) {
  const data = assignmentSchema.parse(input);
  return transaction(async (client) => {
    const result = await client.query<{ revision: number; inside: boolean }>(
      `
      SELECT j.revision,public.ST_Covers(a.boundary,j.geom) AS inside
      FROM dispatch.jobs j
      JOIN dispatch.teams t ON t.id=$2
      JOIN dispatch.areas a ON a.id=t.area_id
      WHERE j.id=$1 FOR UPDATE OF j
    `,
      [data.jobId, data.teamId],
    );
    const job = result.rows[0];
    if (!job) throw new DispatchError("Job or team not found.", 404);
    if (job.revision !== data.revision)
      throw new DispatchError(
        "This job changed in another tab. Refresh before assigning.",
        409,
      );
    if (!job.inside)
      throw new DispatchError(
        "This job lies outside the team’s service area. Assignment was not saved.",
      );
    await client.query(
      `
      UPDATE dispatch.jobs SET team_id=$2,revision=revision+1 WHERE id=$1
    `,
      [data.jobId, data.teamId],
    );
    return { revision: job.revision + 1 };
  });
}
export async function saveMap(input: MapState) {
  const state = mapStateSchema.parse(input);
  return transaction(async (client) => {
    const result = await client.query(`
      SELECT revision FROM dispatch.map_state WHERE id='dispatch' FOR UPDATE
    `);
    if (result.rows[0].revision !== state.revision)
      throw new DispatchError(
        "The saved view changed in another tab. Reload before saving.",
        409,
      );
    if (
      !(
        await client.query("SELECT 1 FROM dispatch.areas WHERE id=$1", [
          state.areaId,
        ])
      ).rowCount
    )
      throw new DispatchError("Select an existing service area.");
    await client.query(
      `
      UPDATE dispatch.map_state SET longitude=$1,latitude=$2,zoom=$3,
        area_id=$4,mode=$5,revision=revision+1 WHERE id='dispatch'
    `,
      [state.longitude, state.latitude, state.zoom, state.areaId, state.mode],
    );
    return { revision: state.revision + 1 };
  });
}
