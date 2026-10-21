-- Run as the admin user. Creates the demo user and three habits with a few
-- weeks of check-ins. Safe to re-run.
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO habit_tracker.users (id, name) OVERRIDING SYSTEM VALUE
VALUES (1, 'Demo user')
ON CONFLICT (id) DO NOTHING;

INSERT INTO habit_tracker.habits (id, user_id, name, created_at) OVERRIDING SYSTEM VALUE
VALUES
  (1, 1, 'Read for 20 minutes', now() - interval '90 days'),
  (2, 1, 'Walk 8,000 steps', now() - interval '90 days'),
  (3, 1, 'No phone after 10pm', now() - interval '30 days')
ON CONFLICT (id) DO NOTHING;
SELECT setval(pg_get_serial_sequence('habit_tracker.habits', 'id'), (SELECT max(id) FROM habit_tracker.habits));
SELECT setval(pg_get_serial_sequence('habit_tracker.users', 'id'), (SELECT max(id) FROM habit_tracker.users));

-- A deterministic pattern: habit 1 has a current streak, habit 2 misses some
-- days, habit 3 was missed yesterday and today.
INSERT INTO habit_tracker.check_ins (habit_id, day)
SELECT h.id, d::date
FROM habit_tracker.habits h
CROSS JOIN generate_series(current_date - 89, current_date, interval '1 day') d
WHERE (h.id = 1 AND (d::date > current_date - 12 OR extract(dow FROM d) <> 0))
   OR (h.id = 2 AND (d::date - (current_date - 89)) % 3 <> 0)
   OR (h.id = 3 AND d::date BETWEEN current_date - 29 AND current_date - 2 AND extract(dow FROM d) NOT IN (5, 6))
ON CONFLICT DO NOTHING;

COMMIT;
