all_messages = """
SELECT count() AS messages
FROM bluesky.bluesky
"""

last_24_hours = """
SELECT
    countIf(bluesky_ts > (now() - ((24 * 60) * 60))) AS last24Hours,
    countIf(
      (bluesky_ts <= (now() - ((24 * 60) * 60))) AND 
      (bluesky_ts > (now() - ((48 * 60) * 60)))
    ) AS previous24Hours
FROM bluesky.bluesky
"""

time_of_day = """
SELECT event, hour_of_day, sum(count) as count
FROM bluesky.events_per_hour_of_day
WHERE event in ['post', 'repost', 'like']
GROUP BY event, hour_of_day
ORDER BY hour_of_day
"""

events_by_day = """
SELECT
    toStartOfDay(bluesky_ts)::Date AS day, 
    count() AS count
FROM bluesky.bluesky
GROUP BY ALL
ORDER BY day ASC
"""

top_post_types = """
SELECT collection,
       sum(posts) AS posts,
       uniqMerge(users) AS users
FROM bluesky.top_post_types
GROUP BY collection
ORDER BY posts DESC
LIMIT 10
"""

most_liked = """
SELECT
    handle,
    sum(likes) AS totalLikes
FROM bluesky.likes_per_user AS lpu
INNER JOIN bluesky.handle_per_user AS hpu ON hpu.did = lpu.did
GROUP BY ALL
ORDER BY totalLikes DESC
LIMIT 100
"""

most_reposted = """
SELECT
    handle,
    sum(reposts) AS totalReposts
FROM bluesky.reposts_per_user AS lpu
INNER JOIN bluesky.handle_per_user AS hpu ON hpu.did = lpu.did
GROUP BY ALL
ORDER BY totalReposts DESC
LIMIT 100
"""

posts_per_language = """
SELECT language AS name, posts AS value
FROM bluesky.posts_per_language
ORDER BY posts DESC
LIMIT 10
"""