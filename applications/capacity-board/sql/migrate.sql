BEGIN;
SELECT pg_advisory_xact_lock(7311002);
CREATE TABLE IF NOT EXISTS capacity_board.schema_versions (
    version integer PRIMARY KEY,
    applied_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
DO $migration$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM capacity_board.schema_versions WHERE version = 1) THEN
        CREATE TABLE capacity_board.boards (
            id uuid PRIMARY KEY,
            title varchar(80) NOT NULL,
            capacity integer NOT NULL CHECK (capacity BETWEEN 1 AND 30),
            revision integer NOT NULL DEFAULT 1 CHECK (revision BETWEEN 1 AND 26)
        );
        CREATE TABLE capacity_board.work_items (
            board_id uuid NOT NULL REFERENCES capacity_board.boards(id),
            id uuid NOT NULL CHECK (id <> '00000000-0000-0000-0000-000000000000'),
            position integer NOT NULL CHECK (position BETWEEN 0 AND 19),
            name varchar(80) NOT NULL CHECK (
                char_length(btrim(name)) BETWEEN 1 AND 80 AND name !~ '[[:cntrl:]]'
            ),
            points integer NOT NULL CHECK (points BETWEEN 0 AND 30),
            PRIMARY KEY (board_id, id),
            UNIQUE (board_id, position)
        );
        CREATE TABLE capacity_board.saves (
            operation_id uuid PRIMARY KEY CHECK (operation_id <> '00000000-0000-0000-0000-000000000000'),
            board_id uuid NOT NULL REFERENCES capacity_board.boards(id),
            fingerprint text NOT NULL CHECK (fingerprint ~ '^[0-9A-F]{64}$'),
            revision integer NOT NULL CHECK (revision BETWEEN 2 AND 26),
            response jsonb NOT NULL CHECK (octet_length(response::text) <= 16000),
            created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
            UNIQUE (board_id, revision)
        );
        INSERT INTO capacity_board.schema_versions(version) VALUES (1);
    END IF;
END
$migration$;
COMMIT;
