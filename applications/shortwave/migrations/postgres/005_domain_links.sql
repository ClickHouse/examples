BEGIN;

CREATE UNIQUE INDEX IF NOT EXISTS custom_domains_account_id_id
  ON custom_domains (account_id, id);

ALTER TABLE links ADD COLUMN IF NOT EXISTS domain_id uuid;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'links_owned_domain_fk' AND conrelid = 'links'::regclass) THEN
    ALTER TABLE links ADD CONSTRAINT links_owned_domain_fk
      FOREIGN KEY (account_id, domain_id) REFERENCES custom_domains (account_id, id)
      ON DELETE RESTRICT;
  END IF;
END $$;

-- Old links keep the default application's slug namespace and URL paths.
ALTER TABLE links DROP CONSTRAINT IF EXISTS links_slug_key;
CREATE UNIQUE INDEX IF NOT EXISTS links_default_slug ON links (slug) WHERE domain_id IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS links_domain_slug ON links (domain_id, slug) WHERE domain_id IS NOT NULL;

COMMIT;
