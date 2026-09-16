\set ON_ERROR_STOP on
-- Run with the runtime login, using verify-full TLS.
DO $$
BEGIN
  IF current_user <> 'link_shortener_app' THEN
    RAISE EXCEPTION 'Verify with the runtime login';
  END IF;
  IF EXISTS (SELECT FROM pg_roles WHERE rolname = current_user
      AND (rolsuper OR rolcreaterole OR rolcreatedb OR rolreplication))
     OR has_schema_privilege(current_user, 'public', 'CREATE') THEN
    RAISE EXCEPTION 'Runtime login has management or schema privileges';
  END IF;
  IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public'
      AND tableowner = current_user) THEN
    RAISE EXCEPTION 'Runtime login must not own application tables';
  END IF;
END $$;
SELECT id FROM accounts LIMIT 1;
SELECT pubname, schemaname, tablename FROM pg_publication_tables
WHERE pubname = 'link_shortener_clickpipe';
SELECT relreplident FROM pg_class WHERE oid = 'public.links'::regclass;
SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid();
