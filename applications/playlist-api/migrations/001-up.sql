\getenv migration_sha MIGRATION_SHA
BEGIN;
SELECT pg_advisory_xact_lock(hashtextextended('playlist_api:001',0));
CREATE TABLE IF NOT EXISTS playlist_api.schema_migrations(version integer PRIMARY KEY,checksum text NOT NULL,applied_at timestamptz NOT NULL DEFAULT now());
SELECT EXISTS(SELECT 1 FROM playlist_api.schema_migrations WHERE version=1) AS applied \gset
\if :applied
SELECT checksum=:'migration_sha' AS same FROM playlist_api.schema_migrations WHERE version=1 \gset
\if :same
\echo Migration already applied with matching checksum.
\else
\echo Migration checksum changed; refusing.
\quit 3
\endif
\else
CREATE TABLE playlist_api.accounts(id uuid PRIMARY KEY);
CREATE TABLE playlist_api.tracks(id uuid PRIMARY KEY,title text NOT NULL CHECK(length(title) BETWEEN 1 AND 80),artist text NOT NULL CHECK(length(artist) BETWEEN 1 AND 80),duration_seconds bigint NOT NULL CHECK(duration_seconds BETWEEN 1 AND 3600));
CREATE TABLE playlist_api.playlists(id uuid PRIMARY KEY,owner_id uuid NOT NULL REFERENCES playlist_api.accounts(id),name text NOT NULL CHECK(length(btrim(name)) BETWEEN 1 AND 80),revision bigint NOT NULL DEFAULT 1 CHECK(revision BETWEEN 1 AND 2147483647));
CREATE INDEX playlists_owner_id_id ON playlist_api.playlists(owner_id,id);
CREATE TABLE playlist_api.items(id uuid PRIMARY KEY,playlist_id uuid NOT NULL REFERENCES playlist_api.playlists(id),track_id uuid NOT NULL REFERENCES playlist_api.tracks(id),position bigint NOT NULL CHECK(position BETWEEN 1 AND 50),CONSTRAINT items_playlist_track UNIQUE(playlist_id,track_id),CONSTRAINT items_playlist_position UNIQUE(playlist_id,position) DEFERRABLE INITIALLY DEFERRED);
-- Narrow SECURITY DEFINER trigger locks the existing account row as owner.
-- It never accepts SQL/text identifiers and uses a fixed search_path.
CREATE FUNCTION playlist_api.playlist_quota() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,playlist_api AS $$
BEGIN
 PERFORM 1 FROM playlist_api.accounts WHERE id=NEW.owner_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Account not found' USING ERRCODE='23503'; END IF;
 IF (SELECT count(*) FROM playlist_api.playlists WHERE owner_id=NEW.owner_id)>=100 THEN RAISE EXCEPTION 'Playlist limit reached' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER playlist_quota BEFORE INSERT ON playlist_api.playlists FOR EACH ROW EXECUTE FUNCTION playlist_api.playlist_quota();
CREATE FUNCTION playlist_api.complete_items() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE total integer; lo bigint; hi bigint;
BEGIN
 SELECT count(*),min(position),max(position) INTO total,lo,hi FROM playlist_api.items WHERE playlist_id=NEW.id;
 IF total NOT BETWEEN 1 AND 50 OR lo<>1 OR hi<>total THEN RAISE EXCEPTION 'Playlist requires complete contiguous positions' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE CONSTRAINT TRIGGER complete_items AFTER INSERT OR UPDATE ON playlist_api.playlists DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION playlist_api.complete_items();
INSERT INTO playlist_api.schema_migrations(version,checksum) VALUES(1,:'migration_sha');
\endif
COMMIT;
