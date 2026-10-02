import type { Database } from "./database.ts";
import type { Search } from "./input.ts";
export type Place = {
  id: number;
  name: string;
  category: string;
  longitude: number;
  latitude: number;
  distanceMeters: number;
};
export function nearbyQuery(sql: Database, search: Search) {
  return sql<Place[]>`
    WITH origin AS (
      SELECT public.ST_SetSRID(
        public.ST_MakePoint(${search.longitude}::double precision, ${search.latitude}::double precision),
        4326
      )::public.geography AS location
    )
    SELECT p.id, p.name, p.category,
      public.ST_X(p.location::public.geometry) AS longitude,
      public.ST_Y(p.location::public.geometry) AS latitude,
      public.ST_Distance(p.location, o.location, true) AS "distanceMeters"
    FROM nearby_places.places p CROSS JOIN origin o
    WHERE public.ST_DWithin(p.location, o.location, ${search.radiusMeters}::double precision, true)
      ${search.category ? sql`AND p.category = ${search.category}` : sql``}
    ORDER BY "distanceMeters", p.id
    LIMIT ${search.limit}
  `;
}
