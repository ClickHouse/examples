\set ON_ERROR_STOP on
GRANT SELECT ON incident_room.users TO incident_app;
GRANT SELECT, INSERT, DELETE ON incident_room.sessions TO incident_app;
GRANT SELECT, INSERT, UPDATE ON incident_room.incidents TO incident_app;
GRANT SELECT, INSERT ON incident_room.entries TO incident_app;
