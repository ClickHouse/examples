// Q1
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
])