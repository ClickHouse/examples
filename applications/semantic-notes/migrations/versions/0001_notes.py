from alembic import op

revision = "0001_notes"
down_revision = None


def upgrade():
    op.execute(
        """
        CREATE TABLE semantic_notes.collection (
            id integer PRIMARY KEY CHECK (id = 1),
            spec jsonb NOT NULL CHECK (spec = '__SPEC__'::jsonb)
        );
        INSERT INTO semantic_notes.collection VALUES (1, '__SPEC__'::jsonb);
        CREATE TABLE semantic_notes.notes (
            id uuid PRIMARY KEY,
            collection_id integer NOT NULL DEFAULT 1 CHECK (collection_id = 1) REFERENCES semantic_notes.collection(id),
            title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 120),
            body text NOT NULL CHECK (length(btrim(body)) BETWEEN 1 AND 4096),
            embedding public.vector(384) NOT NULL CHECK (public.vector_norm(embedding) > 0),
            revision integer NOT NULL DEFAULT 1 CHECK (revision > 0),
            created_at timestamptz NOT NULL DEFAULT now(),
            updated_at timestamptz NOT NULL DEFAULT now()
        );
        CREATE FUNCTION semantic_notes.note_quota() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN
            PERFORM 1 FROM semantic_notes.collection WHERE id = 1 FOR UPDATE;
            IF (SELECT count(*) FROM semantic_notes.notes) >= 100 THEN
                RAISE EXCEPTION 'Notebook supports at most 100 notes' USING ERRCODE = '23514';
            END IF;
            RETURN NEW;
        END $$;
        CREATE TRIGGER note_quota BEFORE INSERT ON semantic_notes.notes FOR EACH ROW EXECUTE FUNCTION semantic_notes.note_quota();
    """.replace(
            "__SPEC__",
            '{"dimensions": 384, "document_format": "title + two newlines + body", "dtype": "float32", "max_tokens_including_special": 256, "model_id": "sentence-transformers/all-MiniLM-L6-v2", "normalize_embeddings": true, "revision": "1110a243fdf4706b3f48f1d95db1a4f5529b4d41"}',
        )
    )


def downgrade():
    op.execute(
        "DROP TABLE semantic_notes.notes; DROP FUNCTION semantic_notes.note_quota(); DROP TABLE semantic_notes.collection;"
    )
