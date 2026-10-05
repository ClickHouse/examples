\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE dispatch_owner;
GRANT SELECT ON dispatch.areas, dispatch.teams, dispatch.jobs, dispatch.map_state TO dispatch_app;
GRANT UPDATE (team_id, revision) ON dispatch.jobs TO dispatch_app;
GRANT UPDATE (longitude, latitude, zoom, area_id, mode, revision) ON dispatch.map_state TO dispatch_app;
COMMIT;
