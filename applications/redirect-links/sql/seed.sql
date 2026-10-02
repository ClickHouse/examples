\set ON_ERROR_STOP on
INSERT INTO redirect_links.accounts(id) VALUES ('north'),('south') ON CONFLICT DO NOTHING;
