// ------------------------------------------------------------------------------------------------------------------------
// -- Q0 - Top event types
// ---------------------------------------------------------------------------------------------------------------------
db.bluesky.aggregate([
  {
    $group: {
      _id: "$commit.collection",
      count: { $sum: 1 }
    }
  },
  {
    $sort: { count: -1 }
  }
]);

// ---------------------------------------------------------------------------------------------------------------------
// -- Q1 - Top event types together with unique users per event type
// ---------------------------------------------------------------------------------------------------------------------
db.bluesky.aggregate([
  {
    $match: {
      "kind": "commit",
      "commit.operation": "create"
    }
  },

  {
    $group: {
      _id: "$commit.collection",
      count: { $sum: 1 },
      users: { $addToSet: "$did" }
    }
  },
  {
    $project: {
      event: "$_id",
      count: 1,
      users: { $size: "$users" }
    }
  },
  {
    $sort: { count: -1 }
  }
]);

// ---------------------------------------------------------------------------------------------------------------------
// -- Q2 - When do people use BlueSky
// ---------------------------------------------------------------------------------------------------------------------
db.bluesky.aggregate([
    {
        $match: {
            "kind": "commit",
            "commit.operation": "create",
            "commit.collection": {
                $in: ["app.bsky.feed.post", "app.bsky.feed.repost", "app.bsky.feed.like"]
            }
        }
    },
    {
        $project: {
            event: "$commit.collection",
            hour_of_day: {
                $hour: {
                    $toDate: { $divide: ["$time_us", 1000] }
                }
            }
        }
    },
    {
        $group: {
            _id: { event: "$event", hour_of_day: "$hour_of_day" },
            count: { $sum: 1 }
        }
    },
    {
        $sort: {
            "_id.hour_of_day": 1,
            "_id.event": 1
        }
    }
]);

// ---------------------------------------------------------------------------------------------------------------------
// -- Q3 - top 3 post veterans
// ---------------------------------------------------------------------------------------------------------------------
db.bluesky.aggregate([
    {
        $match: {
            "kind": "commit",
            "commit.operation": "create",
            "commit.collection": "app.bsky.feed.post"
        }
    },
    {
        $project: {
            user_id: "$did",
            timestamp: { $toDate: { $divide: ["$time_us", 1000] } }
        }
    },
    {
        $group: {
            _id: "$user_id",
            first_post_ts: { $min: "$timestamp" }
        }
    },
    {
        $sort: { first_post_ts: 1 }
    },
    {
        $limit: 3
    }
]);

// ---------------------------------------------------------------------------------------------------------------------
// -- Q4 - top 3 users with longest activity
// ---------------------------------------------------------------------------------------------------------------------
db.bluesky.aggregate([
    {
        $match: {
            "kind": "commit",
            "commit.operation": "create",
            "commit.collection": "app.bsky.feed.post"
        }
    },
    {
        $project: {
            user_id: "$did",
            timestamp: { $toDate: { $divide: ["$time_us", 1000] } }
        }
    },
    {
        $group: {
            _id: "$user_id",
            min_timestamp: { $min: "$timestamp" },
            max_timestamp: { $max: "$timestamp" }
        }
    },
    {
        $project: {
            activity_span: {
                $dateDiff: {
                    startDate: "$min_timestamp",
                    endDate: "$max_timestamp",
                    unit: "millisecond"
                }
            }
        }
    },
    {
        $sort: { activity_span: -1 }
    },
    {
        $limit: 3
    }
]);
