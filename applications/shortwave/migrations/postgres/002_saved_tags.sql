BEGIN;

-- Reusable account vocabulary stays available after a tag is removed from a link.
-- Link membership remains in links.tags for the existing CDC analytics path.
CREATE TABLE IF NOT EXISTS account_tags (
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  name varchar(40) NOT NULL CHECK (length(btrim(name)) > 0),
  PRIMARY KEY (account_id, name)
);

INSERT INTO account_tags (account_id, name)
SELECT DISTINCT account_id, unnest(tags) FROM links
ON CONFLICT DO NOTHING;

-- Existing Cloud runtime role; fresh setups may create their role afterwards.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'link_shortener_app') THEN
    GRANT SELECT, INSERT ON account_tags TO link_shortener_app;
  END IF;
END
$$;

COMMIT;
