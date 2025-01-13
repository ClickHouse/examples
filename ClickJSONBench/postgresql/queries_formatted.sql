------------------------------------------------------------------------------------------------------------------------
-- Q0 - Top event types - approximate number of users
------------------------------------------------------------------------------------------------------------------------
SELECT
    data -> 'commit' ->> 'collection' AS event,
    COUNT(*) as count,
    COUNT(DISTINCT data ->> 'did') AS users
FROM bluesky
WHERE data ->> 'kind' = 'commit'
  AND data -> 'commit' ->> 'operation' = 'create'
GROUP BY event
ORDER BY count DESC;

------------------------------------------------------------------------------------------------------------------------
-- Q1 - Top event types - exact number users
------------------------------------------------------------------------------------------------------------------------
SELECT
    data -> 'commit' ->> 'collection' AS event,
    COUNT(*) as count,
    COUNT(DISTINCT data ->> 'did') AS users
FROM bluesky
WHERE data ->> 'kind' = 'commit'
  AND data -> 'commit' ->> 'operation' = 'create'
GROUP BY event
ORDER BY count DESC;

------------------------------------------------------------------------------------------------------------------------
-- Q2 - When do people use BlueSky
------------------------------------------------------------------------------------------------------------------------
SELECT
    data->'commit'->>'collection' AS event,
    EXTRACT(HOUR FROM TO_TIMESTAMP((data->>'time_us')::BIGINT / 1000000)) AS hour_of_day,
    COUNT(*) AS count
FROM bluesky
WHERE data->>'kind' = 'commit'
  AND data->'commit'->>'operation' = 'create'
  AND data->'commit'->>'collection' IN ('app.bsky.feed.post', 'app.bsky.feed.repost', 'app.bsky.feed.like')
GROUP BY event, hour_of_day
ORDER BY hour_of_day, event;

------------------------------------------------------------------------------------------------------------------------
-- Q3 - top 3 post veterans
------------------------------------------------------------------------------------------------------------------------
SELECT
    data->>'did' AS user_id,
    MIN(
        TIMESTAMP WITH TIME ZONE 'epoch' +
        INTERVAL '1 microsecond' * (data->>'time_us')::BIGINT
    ) AS first_post_ts
FROM bluesky
WHERE data->>'kind' = 'commit'
  AND data->'commit'->>'operation' = 'create'
  AND data->'commit'->>'collection' = 'app.bsky.feed.post'
GROUP BY user_id
ORDER BY first_post_ts ASC
LIMIT 3;

------------------------------------------------------------------------------------------------------------------------
-- Q4 - top 3 users with longest activity
------------------------------------------------------------------------------------------------------------------------
SELECT
    data->>'did' AS user_id,
    EXTRACT(EPOCH FROM (
        MAX(
            TIMESTAMP WITH TIME ZONE 'epoch' +
            INTERVAL '1 microsecond' * (data->>'time_us')::BIGINT
        ) -
        MIN(
            TIMESTAMP WITH TIME ZONE 'epoch' +
            INTERVAL '1 microsecond' * (data->>'time_us')::BIGINT
        )
    )) * 1000 AS activity_span
FROM bluesky
WHERE data->>'kind' = 'commit'
  AND data->'commit'->>'operation' = 'create'
  AND data->'commit'->>'collection' = 'app.bsky.feed.post'
GROUP BY user_id
ORDER BY activity_span DESC
LIMIT 3;

------------------------------------------------------------------------------------------------------------------------
-- Q5 - (self-)join query - top 3 most liked posts
------------------------------------------------------------------------------------------------------------------------
WITH
    T1 AS (
        SELECT
            data->'commit'->'record'->'subject'->>'cid' AS post_id,
            COUNT(*) AS likes
        FROM bluesky
        WHERE data->>'kind' = 'commit'
          AND data->'commit'->>'operation' = 'create'
          AND data->'commit'->>'collection' = 'app.bsky.feed.like'
        GROUP BY post_id
    ),
    T2 AS (
        SELECT
            (data->'commit'->>'cid') AS post_id,
            (data->'commit'->'record'->>'text') AS post_text
        FROM bluesky
        WHERE data->>'kind' = 'commit'
          AND data->'commit'->>'operation' = 'create'
          AND data->'commit'->>'collection' = 'app.bsky.feed.post'
    )
SELECT
    t1.likes,
    t2.post_text
FROM T1 t1
INNER JOIN T2 t2 ON t1.post_id = t2.post_id
ORDER BY t1.likes DESC
LIMIT 3;