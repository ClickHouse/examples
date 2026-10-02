\set ON_ERROR_STOP on
-- Synthetic labels at explicit test coordinates, not a directory of real businesses.
INSERT INTO nearby_places.places (id, name, category, location)
SELECT id, name, category,
  public.ST_SetSRID(public.ST_MakePoint(longitude, latitude), 4326)::public.geography
FROM (VALUES
  (1, 'Anchor Cafe', 'cafe', -0.120::double precision, 51.500::double precision),
  (2, 'Garden Library', 'library', -0.119, 51.501),
  (3, 'Quay Park', 'park', -0.122, 51.499),
  (4, 'Courtyard Cafe', 'cafe', -0.120, 51.500),
  (5, 'Further Cafe', 'cafe', -0.110, 51.500),
  (6, 'Equator Library', 'library', 0.000, 0.000),
  (7, 'Equator East Cafe', 'cafe', 0.010, 0.000),
  (8, 'Equator North Park', 'park', 0.000, 0.010),
  (9, 'Dateline East Cafe', 'cafe', 179.999, 0.000),
  (10, 'Dateline West Park', 'park', -179.999, 0.000),
  (11, 'Off-axis Library', 'library', 12.000, 45.000),
  (12, 'Polar Garden', 'park', 0.000, 89.999)
) AS fixture(id, name, category, longitude, latitude)
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, category = EXCLUDED.category,
  location = EXCLUDED.location;
ANALYZE nearby_places.places;
