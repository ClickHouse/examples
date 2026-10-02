\set ON_ERROR_STOP on
BEGIN;
INSERT INTO heartbeats.projects VALUES('north'),('south') ON CONFLICT DO NOTHING;
INSERT INTO heartbeats.devices(project,id)
SELECT project,device FROM (VALUES('north'),('south')) AS p(project),
    (VALUES('meter-a'),('meter-b'),('meter-c')) AS d(device)
ON CONFLICT DO NOTHING;
COMMIT;
