CREATE TABLE webhook.integrations (
    id UUID PRIMARY KEY,
    name TEXT NOT NULL UNIQUE
);
CREATE TABLE webhook.events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id UUID NOT NULL REFERENCES webhook.integrations(id),
    external_event_id TEXT NOT NULL CHECK (length(external_event_id) BETWEEN 1 AND 80),
    payload JSONB NOT NULL,
    payload_sha256 TEXT NOT NULL CHECK (length(payload_sha256) = 64),
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processed', 'failed')),
    attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 3),
    last_error TEXT,
    available_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    processed_at TIMESTAMPTZ,
    UNIQUE (integration_id, external_event_id),
    CHECK ((status = 'processed') = (processed_at IS NOT NULL)),
    CHECK (status <> 'failed' OR (attempts = 3 AND last_error IS NOT NULL))
);
CREATE INDEX events_ready ON webhook.events (available_at, created_at, id) WHERE status = 'pending';
CREATE TABLE webhook.activity (
    event_id UUID PRIMARY KEY REFERENCES webhook.events(id),
    integration_id UUID NOT NULL REFERENCES webhook.integrations(id),
    path TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE webhook.counters (
    integration_id UUID PRIMARY KEY REFERENCES webhook.integrations(id),
    event_count BIGINT NOT NULL DEFAULT 0 CHECK (event_count >= 0)
);
GRANT SELECT ON webhook.integrations, webhook.events, webhook.counters TO webhook_receiver;
GRANT INSERT (integration_id, external_event_id, payload, payload_sha256) ON webhook.events TO webhook_receiver;
GRANT SELECT ON webhook.integrations, webhook.events, webhook.counters TO webhook_worker;
GRANT UPDATE (status, attempts, last_error, available_at, processed_at) ON webhook.events TO webhook_worker;
GRANT UPDATE (event_count) ON webhook.counters TO webhook_worker;
GRANT INSERT ON webhook.activity TO webhook_worker;
