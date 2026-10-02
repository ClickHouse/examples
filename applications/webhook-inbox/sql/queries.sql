-- name: IntegrationExists :one
SELECT EXISTS (SELECT 1 FROM webhook.integrations WHERE id = $1);

-- name: InsertEvent :one
INSERT INTO webhook.events (integration_id, external_event_id, payload, payload_sha256)
VALUES ($1, $2, $3, $4) ON CONFLICT (integration_id, external_event_id) DO NOTHING
RETURNING *;

-- name: GetEvent :one
SELECT * FROM webhook.events WHERE integration_id = $1 AND external_event_id = $2;

-- name: GetCounter :one
SELECT event_count FROM webhook.counters WHERE integration_id = $1;

-- name: ClaimEvent :one
SELECT * FROM webhook.events
WHERE status = 'pending' AND available_at <= clock_timestamp()
ORDER BY available_at, created_at, id
LIMIT 1 FOR UPDATE SKIP LOCKED;

-- name: RecordActivity :exec
INSERT INTO webhook.activity (event_id, integration_id, path) VALUES ($1, $2, $3);

-- name: IncrementCounter :execrows
UPDATE webhook.counters SET event_count = event_count + 1 WHERE integration_id = $1;

-- name: CompleteEvent :exec
UPDATE webhook.events SET status = 'processed', attempts = attempts + 1,
    processed_at = clock_timestamp(), last_error = NULL WHERE id = $1;

-- name: FailEvent :exec
UPDATE webhook.events SET attempts = attempts + 1,
    status = CASE WHEN attempts + 1 >= 3 THEN 'failed' ELSE 'pending' END,
    last_error = $2, available_at = clock_timestamp() + ((attempts + 1) * interval '1 second')
WHERE id = $1;
