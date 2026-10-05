GRANT SELECT ON products, quotes, quote_lines TO quote_catalogue_app;
GRANT UPDATE (days, revision, updated_at) ON quotes TO quote_catalogue_app;
GRANT INSERT, DELETE ON quote_lines TO quote_catalogue_app;
