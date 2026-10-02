GRANT USAGE ON SCHEMA csv_review TO csv_app;
GRANT SELECT, INSERT, UPDATE ON csv_review.batches, csv_review.staged_rows TO csv_app;
GRANT SELECT, INSERT ON csv_review.catalogue_items TO csv_app;
REVOKE ALL ON csv_review.alembic_version FROM csv_app;
