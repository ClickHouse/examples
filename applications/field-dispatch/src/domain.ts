import { z } from "zod";
import type { Feature, Polygon } from "geojson";

export const viewportSchema = z
  .object({
    west: z.coerce.number().finite().min(-1.53).max(-1.39),
    south: z.coerce.number().finite().min(53.31).max(53.43),
    east: z.coerce.number().finite().min(-1.53).max(-1.39),
    north: z.coerce.number().finite().min(53.31).max(53.43),
  })
  .refine(
    (v) =>
      v.east > v.west &&
      v.north > v.south &&
      v.east - v.west <= 0.14 &&
      v.north - v.south <= 0.12,
    "Use a bounded viewport around the synthetic town.",
  );
export const assignmentSchema = z
  .object({
    jobId: z.uuid(),
    teamId: z.uuid(),
    revision: z.number().int().positive().max(2147483646),
  })
  .strict();
export const mapStateSchema = z
  .object({
    longitude: z.number().finite().min(-1.52).max(-1.4),
    latitude: z.number().finite().min(53.32).max(53.42),
    zoom: z.number().finite().min(12).max(16),
    areaId: z.uuid(),
    mode: z.enum(["assignments", "priority"]),
    revision: z.number().int().positive().max(2147483646),
  })
  .strict();
export type Viewport = z.infer<typeof viewportSchema>;
export type MapState = z.infer<typeof mapStateSchema>;
export type Area = {
  id: string;
  name: string;
  color: string;
  feature: Feature<Polygon>;
};
export type Team = {
  id: string;
  name: string;
  areaId: string;
  position: [number, number];
};
export type Job = {
  id: string;
  code: string;
  title: string;
  priority: "routine" | "urgent";
  position: [number, number];
  teamId: string | null;
  revision: number;
};
export type Bootstrap = { areas: Area[]; teams: Team[]; state: MapState };
