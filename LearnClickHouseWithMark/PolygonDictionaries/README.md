# Polygon Dictionaries in ClickHouse

Video: https://www.youtube.com/watch?v=FyRsriQp46E

Install ClickHouse

```bash
curl https://clickhouse.com/ | sh
```

Launch ClickHouse

```bash
./clickhouse local -m
```

Query Geo polygons

```sql
FROM url(
  'https://datahub.io/core/geo-countries/r/0.geojson', 
  JSONAsString
)
SELECT arrayJoin(JSONExtractArrayRaw(json, 'features')) AS json
LIMIT 1
FORMAT Vertical
SETTINGS max_http_get_redirects=1;
```

Import polygons

```sql
CREATE TABLE countries
Engine = MergeTree
ORDER BY name
AS

WITH features AS (
    FROM url(
        'https://datahub.io/core/geo-countries/r/0.geojson',
        JSONAsString
    )
    SELECT arrayJoin(JSONExtractArrayRaw(json, 'features')) AS json
)

FROM features
SELECT JSONExtractString(JSONExtractString(json, 'properties'), 'ADMIN') AS name,
       JSONExtractString(JSONExtractRaw(json, 'geometry'), 'type') AS type,
       if(type = 'Polygon',
         [JSONExtract(
            JSONExtractRaw(JSONExtractRaw(json, 'geometry'), 'coordinates'),
          'Polygon')
         ],
         JSONExtract(
          JSONExtractRaw(JSONExtractRaw(json, 'geometry'), 'coordinates'),
        'MultiPolygon')
       ) AS coordinates
SETTINGS max_http_get_redirects=1;
```

Find the polygon for a point

```sql
FROM countries
SELECT name
WHERE arrayExists(
  cord -> pointInPolygon((9.8051400, 53.7280), cord),
  coordinates
);
```

Don't make everything nullable when processing CSV file

```sql
SET schema_inference_make_columns_nullable=0;
```

Count the number of locations in UK polygons

```sql
WITH (
      SELECT coordinates
      FROM countries
      WHERE name = 'United Kingdom'
  ) AS uk
SELECT count()
FROM file('locations.csv', CSVWithNames)
WHERE arrayExists(cord -> pointInPolygon((long, lat), cord), uk);
```

Create polygon dictionary

```sql
CREATE DICTIONARY country_polygons
(
   `name` String,
   `coordinates` MultiPolygon
)
PRIMARY KEY coordinates
SOURCE(CLICKHOUSE(TABLE 'countries'))
LIFETIME(MIN 0 MAX 0)
LAYOUT(POLYGON(STORE_POLYGON_KEY_COLUMN 1));
```

Load dictionary into memory

```sql
SELECT dictGet(country_polygons, 'name', (9.8051400, 53.7280));
```


Count the number of locations in UK polygons with a dictionary

```sql
WITH (
      SELECT coordinates
      FROM countries
      WHERE name = 'United Kingdom'
  ) AS uk
SELECT count()
FROM file('locations.csv', CSVWithNames)
WHERE dictGet(country_polygons, 'name', (long, lat))  = 'United Kingdom';
```
