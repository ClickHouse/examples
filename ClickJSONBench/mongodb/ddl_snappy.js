db.createCollection(
   "bluesky",
   { storageEngine: { wiredTiger: { configString: "block_compressor=snappy" } } }
);

db.bluesky.createIndex({"kind": 1, "commit.operation": 1, "commit.collection": 1, "time_us": 1});