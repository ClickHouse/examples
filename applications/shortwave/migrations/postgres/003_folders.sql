BEGIN;

-- Flat, account-owned folders. Keep CDC's links table unchanged.
CREATE TABLE IF NOT EXISTS folders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  name varchar(80) NOT NULL CHECK (length(trim(name)) > 0),
  UNIQUE (account_id, id)
);
CREATE UNIQUE INDEX IF NOT EXISTS folders_account_name ON folders (account_id, lower(name));

-- One optional folder per link; deleting a folder only removes membership.
CREATE TABLE IF NOT EXISTS link_folders (
  link_id uuid PRIMARY KEY,
  account_id uuid NOT NULL,
  folder_id uuid NOT NULL,
  FOREIGN KEY (account_id, link_id) REFERENCES links(account_id, id) ON DELETE CASCADE,
  FOREIGN KEY (account_id, folder_id) REFERENCES folders(account_id, id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS link_folders_account_folder ON link_folders (account_id, folder_id);

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'link_shortener_app') THEN
    GRANT SELECT, INSERT, UPDATE, DELETE ON folders, link_folders TO link_shortener_app;
  END IF;
END $$;

COMMIT;
