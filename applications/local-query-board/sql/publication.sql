-- Run as the service owner after the migration-owned tables exist.
CREATE PUBLICATION electric_publication_local_query_board FOR TABLE planning.projects, planning.tasks;
-- PostgreSQL requires temporary CREATE permission when transferring ownership.
GRANT CREATE ON DATABASE postgres TO planning_sync;
ALTER PUBLICATION electric_publication_local_query_board OWNER TO planning_sync;
REVOKE CREATE ON DATABASE postgres FROM planning_sync;
