\set ON_ERROR_STOP on
INSERT INTO habits.habit (id, owner_id, name, archived, created_at)
VALUES ('00000000-0000-0000-0000-000000000001', 'user-a', 'Read a chapter', false, now()),
       ('00000000-0000-0000-0000-000000000002', 'user-b', 'Stretch', false, now())
ON CONFLICT (id) DO NOTHING;
INSERT INTO habits.check_in (id, habit_id, completed_on, created_at)
VALUES ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', DATE '2026-10-01', now())
ON CONFLICT (habit_id, completed_on) DO NOTHING;
