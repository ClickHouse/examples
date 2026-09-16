BEGIN;

CREATE TABLE IF NOT EXISTS accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clerk_user_id text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL REFERENCES accounts(id),
  slug varchar(48) NOT NULL UNIQUE CHECK (slug ~ '^[a-zA-Z0-9][a-zA-Z0-9_-]{2,47}$'),
  title varchar(160) NOT NULL DEFAULT '',
  destination text NOT NULL,
  resolved_url text NOT NULL,
  utm jsonb NOT NULL DEFAULT '{}',
  tags text[] NOT NULL DEFAULT '{}',
  enabled boolean NOT NULL DEFAULT true,
  revision bigint NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (account_id, id)
);
CREATE INDEX IF NOT EXISTS links_account_created ON links (account_id, created_at DESC);
CREATE INDEX IF NOT EXISTS links_tags ON links USING gin (tags);

CREATE TABLE IF NOT EXISTS utm_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL REFERENCES accounts(id),
  name varchar(80) NOT NULL,
  values jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (account_id, name)
);

CREATE TABLE IF NOT EXISTS qr_styles (
  link_id uuid PRIMARY KEY,
  account_id uuid NOT NULL,
  style jsonb NOT NULL,
  FOREIGN KEY (account_id, link_id) REFERENCES links(account_id, id) ON DELETE CASCADE
);

-- This durable queue is deliberately excluded from the CDC publication.
-- A redirect is acknowledged only after its event is committed here.
CREATE TABLE IF NOT EXISTS click_outbox (
  event_id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES accounts(id),
  event jsonb NOT NULL,
  attempts integer NOT NULL DEFAULT 0,
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS click_outbox_ready ON click_outbox (next_attempt_at, created_at);
CREATE INDEX IF NOT EXISTS click_outbox_account ON click_outbox (account_id);

COMMIT;
