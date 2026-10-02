\set ON_ERROR_STOP on
GRANT USAGE ON SCHEMA redirect_links TO redirects_app;
GRANT SELECT ON redirect_links.accounts,redirect_links.links TO redirects_app;
GRANT INSERT ON redirect_links.links TO redirects_app;
GRANT UPDATE(link_count) ON redirect_links.accounts TO redirects_app;
GRANT UPDATE(disabled_at,revision) ON redirect_links.links TO redirects_app;
GRANT USAGE ON SEQUENCE redirect_links.links_id_seq TO redirects_app;
