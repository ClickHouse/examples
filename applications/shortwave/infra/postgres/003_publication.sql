-- Run as the service administrator, after tables and grants exist.
BEGIN;
DO $$
BEGIN
  IF current_setting('wal_level') <> 'logical' THEN
    RAISE EXCEPTION 'Enable wal_level=logical before creating the ClickPipe';
  END IF;
  IF NOT EXISTS (SELECT FROM pg_publication WHERE pubname = 'link_shortener_clickpipe') THEN
    CREATE PUBLICATION link_shortener_clickpipe FOR TABLE public.links;
  END IF;
  IF (SELECT count(*) FROM pg_publication_tables
      WHERE pubname = 'link_shortener_clickpipe') <> 1
     OR NOT EXISTS (SELECT FROM pg_publication_tables
       WHERE pubname = 'link_shortener_clickpipe'
         AND schemaname = 'public' AND tablename = 'links') THEN
    RAISE EXCEPTION 'link_shortener_clickpipe must contain only public.links';
  END IF;
END $$;
COMMIT;
