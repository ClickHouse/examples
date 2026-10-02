-- Execute as directory_owner after migrations and seeding.
GRANT USAGE ON SCHEMA directory TO directory_app;
GRANT SELECT ON directory.users, directory.skills, directory.user_skills TO directory_app;
GRANT UPDATE (display_name, biography, location, revision, updated_at) ON directory.users TO directory_app;
GRANT INSERT, DELETE ON directory.user_skills TO directory_app;
