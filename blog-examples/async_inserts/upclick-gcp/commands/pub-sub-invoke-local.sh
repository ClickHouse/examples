#!/usr/bin/env bash
# a helper local bash script to trigger the function locally (emulates the pub/sub payload)
curl localhost:8080 \
  -X POST \
  -H "Content-Type: application/json" \
  -H "ce-id: 123451234512345" \
  -H "ce-specversion: 1.0" \
  -H "ce-time: 2020-01-02T12:34:56.789Z" \
  -H "ce-type: google.cloud.pubsub.topic.v1.messagePublished" \
  -H "ce-source: //pubsub.googleapis.com/projects/MY-PROJECT/topics/MY-TOPIC" \
  -d '{
    "message": {
      "data": "eyJ0YXJnZXQiOiJ3d3cuY2xpY2tob3VzZS5jb20ifQ=="
    }
  }'
    
# echo -n '{"target":"www.clickhouse.com"}' | base64
# eyJ0YXJnZXQiOiJ3d3cuY2xpY2tob3VzZS5jb20ifQ==

