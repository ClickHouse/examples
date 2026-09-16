BEGIN;

-- Claims prove ownership only. They do not change link routing or slug scope.
CREATE TABLE IF NOT EXISTS custom_domains (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  hostname varchar(229) NOT NULL CHECK (hostname = lower(hostname)),
  verification_token varchar(64) NOT NULL CHECK (verification_token ~ '^[0-9a-f]{64}$'),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'verified')),
  verified_at timestamptz,
  last_checked_at timestamptz,
  verification_error text,
  verification_attempt uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (account_id, hostname),
  CHECK ((status = 'verified') = (verified_at IS NOT NULL))
);

-- Pending claims cannot prevent another account proving ownership.
CREATE UNIQUE INDEX IF NOT EXISTS custom_domains_verified_hostname
  ON custom_domains (hostname) WHERE status = 'verified';

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'link_shortener_app') THEN
    GRANT SELECT, INSERT, UPDATE, DELETE ON custom_domains TO link_shortener_app;
  END IF;
END $$;

COMMIT;
