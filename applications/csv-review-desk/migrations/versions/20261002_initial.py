"""Durable staged rows and atomic catalogue approval."""

from alembic import op

revision = "20261002_initial"
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    op.execute("""
CREATE TABLE batches (
 id uuid PRIMARY KEY, filename varchar(120) NOT NULL,
 status varchar(16) NOT NULL DEFAULT 'pending', revision integer NOT NULL DEFAULT 1 CHECK(revision >= 1),
 row_count integer NOT NULL CHECK(row_count BETWEEN 1 AND 200),
 created_at timestamptz NOT NULL DEFAULT now(), approved_at timestamptz,
 CONSTRAINT batch_state CHECK((status = 'pending' AND approved_at IS NULL) OR (status = 'approved' AND approved_at IS NOT NULL))
);
CREATE INDEX batches_recent ON batches(created_at DESC, id);
CREATE TABLE staged_rows (
 id uuid PRIMARY KEY, batch_id uuid NOT NULL REFERENCES batches(id),
 position integer NOT NULL CHECK(position BETWEEN 0 AND 199),
 sku text NOT NULL CHECK(char_length(sku) <= 80),
 name text NOT NULL CHECK(char_length(name) <= 240),
 price_cents text NOT NULL CHECK(char_length(price_cents) <= 32),
 errors jsonb NOT NULL CHECK(jsonb_typeof(errors) = 'array'),
 UNIQUE(batch_id, position), UNIQUE(id, batch_id)
);
CREATE TABLE catalogue_items (
 sku varchar(40) PRIMARY KEY CHECK(sku ~ '^[A-Z0-9][A-Z0-9_-]{0,39}$'),
 name varchar(120) NOT NULL CHECK(char_length(name) BETWEEN 1 AND 120 AND btrim(name) = name),
 price_cents integer NOT NULL CHECK(price_cents BETWEEN 0 AND 1000000000),
 source_batch_id uuid NOT NULL REFERENCES batches(id), source_row_id uuid NOT NULL UNIQUE,
 FOREIGN KEY(source_row_id, source_batch_id) REFERENCES staged_rows(id, batch_id)
);
CREATE INDEX catalogue_batch ON catalogue_items(source_batch_id);
CREATE FUNCTION guard_stage() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE parent_status text;
BEGIN
 IF TG_OP = 'UPDATE' AND (NEW.id, NEW.batch_id, NEW.position) IS DISTINCT FROM (OLD.id, OLD.batch_id, OLD.position) THEN
  RAISE EXCEPTION 'Staged row identity is immutable' USING ERRCODE = '23514';
 END IF;
 SELECT status INTO parent_status FROM batches WHERE id = COALESCE(NEW.batch_id, OLD.batch_id) FOR UPDATE;
 IF parent_status IS DISTINCT FROM 'pending' THEN
  RAISE EXCEPTION 'Approved rows are immutable' USING ERRCODE = '23514';
 END IF;
 IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END $$;
CREATE TRIGGER staged_guard BEFORE INSERT OR UPDATE OR DELETE ON staged_rows FOR EACH ROW EXECUTE FUNCTION guard_stage();
CREATE FUNCTION guard_batch() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF (NEW.id, NEW.row_count, NEW.created_at, NEW.filename) IS DISTINCT FROM (OLD.id, OLD.row_count, OLD.created_at, OLD.filename)
    OR NEW.revision <= OLD.revision THEN
  RAISE EXCEPTION 'Batch identity or revision invalid' USING ERRCODE = '23514';
 END IF;
 IF OLD.status = 'approved' THEN
  RAISE EXCEPTION 'Approved batch is immutable' USING ERRCODE = '23514';
 END IF;
 IF NEW.status = 'approved' AND ((SELECT count(*) FROM catalogue_items WHERE source_batch_id = NEW.id) <> NEW.row_count
  OR (SELECT count(*) FROM staged_rows WHERE batch_id = NEW.id) <> NEW.row_count
  OR EXISTS(SELECT 1 FROM staged_rows WHERE batch_id = NEW.id AND errors <> '[]'::jsonb)) THEN
  RAISE EXCEPTION 'Approval requires a complete valid publication' USING ERRCODE = '23514';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER batch_guard BEFORE UPDATE ON batches FOR EACH ROW EXECUTE FUNCTION guard_batch();
""")


def downgrade():
    op.execute("""
DROP TABLE catalogue_items;
DROP TABLE staged_rows;
DROP TABLE batches;
DROP FUNCTION guard_stage();
DROP FUNCTION guard_batch();
""")
