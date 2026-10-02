BEGIN;
SELECT pg_advisory_xact_lock(721151);
CREATE TABLE IF NOT EXISTS redirect_links.schema_versions (
    version integer PRIMARY KEY,
    applied_at timestamptz NOT NULL DEFAULT now()
);
DO $migration$
BEGIN
    IF NOT EXISTS (SELECT FROM redirect_links.schema_versions WHERE version = 1) THEN
        CREATE TABLE redirect_links.accounts (
            id text PRIMARY KEY CHECK (id IN ('north','south')),
            link_count integer NOT NULL DEFAULT 0 CHECK (link_count BETWEEN 0 AND 20)
        );
        CREATE TABLE redirect_links.links (
            id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY CHECK (id > 0),
            account text NOT NULL REFERENCES redirect_links.accounts(id),
            slug text NOT NULL CONSTRAINT links_slug_unique UNIQUE,
            destination text NOT NULL,
            expires_at timestamptz,
            disabled_at timestamptz,
            revision bigint NOT NULL DEFAULT 1,
            created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
            CHECK (slug ~ '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$'),
            CHECK (slug NOT IN ('health','links','admin','api','static')),
            CHECK (octet_length(destination) <= 2048 AND destination ~ '^https?://'
                AND destination !~ '[[:cntrl:]]'),
            CHECK ((revision = 1 AND disabled_at IS NULL) OR (revision = 2 AND disabled_at IS NOT NULL))
        );
        CREATE INDEX links_account_id ON redirect_links.links(account,id DESC);
        INSERT INTO redirect_links.schema_versions(version) VALUES (1);
    END IF;
END;
$migration$;
COMMIT;
