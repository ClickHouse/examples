\getenv owner_password PG_OWNER_PASSWORD
\getenv app_password PG_APP_PASSWORD
BEGIN;
CREATE ROLE expense_review_owner LOGIN PASSWORD :'owner_password';
CREATE ROLE expense_review_app LOGIN PASSWORD :'app_password';
CREATE SCHEMA expense_review AUTHORIZATION expense_review_owner;
GRANT USAGE ON SCHEMA expense_review TO expense_review_app;
ALTER ROLE expense_review_owner SET search_path=expense_review,pg_catalog;
ALTER ROLE expense_review_app SET search_path=expense_review,pg_catalog;
ALTER ROLE expense_review_app SET statement_timeout='5s';
ALTER ROLE expense_review_app SET lock_timeout='3s';
COMMIT;
