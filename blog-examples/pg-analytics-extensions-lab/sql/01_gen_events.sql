-- Deterministic synthetic events dataset. Same SQL, same hash functions => identical rows on every PG 17 instance.
-- :rows is passed by psql -v rows=50000000
\timing on
DROP TABLE IF EXISTS events;
DROP TABLE IF EXISTS users;
CREATE TABLE events (
  event_id    bigint PRIMARY KEY,
  event_time  timestamptz NOT NULL,
  user_id     bigint NOT NULL,
  event_type  text NOT NULL,
  country     text NOT NULL,
  url         text NOT NULL,
  duration_ms int NOT NULL,
  revenue     numeric(10,2) NOT NULL
);
-- 50M rows spread over ~180 days starting 2026-01-01 UTC (0.311 s per row)
INSERT INTO events
SELECT i,
       timestamptz '2026-01-01 00:00:00+00' + (i * 0.311) * interval '1 second',
       (abs(hashint8extended(i, 0)) % 5000000) + 1,
       (ARRAY['page_view','page_view','page_view','page_view','page_view','click','click','click','scroll','search',
              'add_to_cart','remove_from_cart','checkout_start','purchase','signup','login','logout','share','video_play','error'])
              [1 + abs(hashint8extended(i, 1)) % 20],
       (ARRAY['US','GB','DE','FR','IN','BR','JP','CA','AU','NL','ES','IT','SE','PL','MX','KR','SG','ZA','AR','IE',
              'CH','BE','AT','DK','NO','FI','PT','NZ','IL','TR','ID','TH','VN','PH','MY','EG','NG','KE','CO','CL'])
              [1 + abs(hashint8extended(i, 2)) % 40],
       'https://shop.example.com/' || (ARRAY['products','category','search','cart','checkout','account','blog','help'])[1 + abs(hashint8extended(i, 3)) % 8]
              || '/' || (abs(hashint8extended(i, 4)) % 100000)::text,
       (abs(hashint8extended(i, 5)) % 30000)::int,
       CASE WHEN abs(hashint8extended(i, 6)) % 10 = 0 THEN ((abs(hashint8extended(i, 7)) % 50000) / 100.0)::numeric(10,2) ELSE 0 END
FROM generate_series(1, :rows) AS i;
CREATE INDEX events_event_time_idx ON events (event_time);
-- 5M-row users dimension
CREATE TABLE users (
  user_id     bigint PRIMARY KEY,
  signup_date date NOT NULL,
  plan        text NOT NULL,
  country     text NOT NULL
);
INSERT INTO users
SELECT u,
       date '2020-01-01' + (abs(hashint8extended(u, 10)) % 2200)::int,
       (ARRAY['free','free','free','free','free','free','pro','pro','team','enterprise'])[1 + abs(hashint8extended(u, 11)) % 10],
       (ARRAY['US','GB','DE','FR','IN','BR','JP','CA','AU','NL'])[1 + abs(hashint8extended(u, 12)) % 10]
FROM generate_series(1, 5000000) AS u;
VACUUM ANALYZE events;
VACUUM ANALYZE users;
SELECT pg_size_pretty(pg_total_relation_size('events')) AS events_size, pg_size_pretty(pg_total_relation_size('users')) AS users_size,
       (SELECT count(*) FROM events) AS n_events, (SELECT count(*) FROM users) AS n_users;
