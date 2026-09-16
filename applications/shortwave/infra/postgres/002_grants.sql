-- Run as link_shortener_migration after the numbered schema migrations.
BEGIN;
GRANT SELECT, INSERT, UPDATE, DELETE ON
  accounts, links, utm_templates, qr_styles, click_outbox, account_tags,
  folders, link_folders, custom_domains
TO link_shortener_app;
GRANT SELECT ON links TO link_shortener_cdc;

-- Preserve unchanged large text and array values on CDC updates.
ALTER TABLE links REPLICA IDENTITY FULL;
COMMIT;
