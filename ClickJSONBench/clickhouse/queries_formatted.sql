------------------------------------------------------------------------------------------------------------------------
-- Q0 - Top event types - approximate number of users
------------------------------------------------------------------------------------------------------------------------
SELECT
    data.commit.collection AS event,
    count() AS count,
	uniq(data.did) AS users
FROM bluesky
WHERE data.kind = 'commit'
  AND data.commit.operation = 'create'
GROUP BY event
ORDER BY count DESC;

------------------------------------------------------------------------------------------------------------------------
-- Q1 - Top event types - exact number users
------------------------------------------------------------------------------------------------------------------------
SELECT
    data.commit.collection AS event,
    count() AS count,
	uniqExact(data.did) AS users
FROM bluesky
WHERE data.kind = 'commit'
  AND data.commit.operation = 'create'
GROUP BY event
ORDER BY count DESC;

------------------------------------------------------------------------------------------------------------------------
-- Q2 - When do people use BlueSky
------------------------------------------------------------------------------------------------------------------------
SELECT
    data.commit.collection AS event,
    toHour(fromUnixTimestamp64Micro(data.time_us)) as hour_of_day,
    count() AS count
FROM bluesky
WHERE data.kind = 'commit'
  AND data.commit.operation = 'create'
  AND data.commit.collection in ['app.bsky.feed.post', 'app.bsky.feed.repost', 'app.bsky.feed.like']
GROUP BY event, hour_of_day
ORDER BY hour_of_day, event;

------------------------------------------------------------------------------------------------------------------------
-- Q3 - top 3 post veterans
------------------------------------------------------------------------------------------------------------------------
SELECT
    data.did::String as user_id,
    min(fromUnixTimestamp64Micro(data.time_us)) as first_post_ts
FROM bluesky
WHERE data.kind = 'commit'
  AND data.commit.operation = 'create'
  AND data.commit.collection = 'app.bsky.feed.post'
GROUP BY user_id
ORDER BY first_post_ts ASC
LIMIT 3;

------------------------------------------------------------------------------------------------------------------------
-- Q4 - top 3 users with longest activity
------------------------------------------------------------------------------------------------------------------------
SELECT
    data.did::String as user_id,
    date_diff(
        'milliseconds',
        min(fromUnixTimestamp64Micro(data.time_us)),
        max(fromUnixTimestamp64Micro(data.time_us))) AS activity_span
FROM bluesky
WHERE data.kind = 'commit'
  AND data.commit.operation = 'create'
  AND data.commit.collection = 'app.bsky.feed.post'
GROUP BY user_id
ORDER BY activity_span DESC
LIMIT 3;

------------------------------------------------------------------------------------------------------------------------
-- Q5 - (self-)join query - top 3 most liked posts
------------------------------------------------------------------------------------------------------------------------
WITH
    T1 AS (
        SELECT
            data.commit.record.subject.cid::String as post_id,
            count() as likes
        FROM bluesky
        WHERE data.kind = 'commit'
          AND data.commit.operation = 'create'
          AND data.commit.collection = 'app.bsky.feed.like'
        GROUP BY post_id
    ),
    T2 AS (
        SELECT
            data.commit.cid::String as post_id,
            data.commit.record.text::String as post_text
        FROM bluesky
        WHERE data.kind = 'commit'
          AND data.commit.operation = 'create'
          AND data.commit.collection = 'app.bsky.feed.post'
    )
SELECT
    t1.likes,
    t2.post_text
FROM T1 t1 INNER JOIN T2 t2 ON t1.post_id = t2.post_id
ORDER BY likes DESC
LIMIT 3;