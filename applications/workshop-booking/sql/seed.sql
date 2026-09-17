-- Run after migrations using the migrator credentials.
-- Re-running keeps existing workshop dates and bookings intact.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE workshop_booking_owner;

INSERT INTO workshop_booking.attendees (id, name, email) VALUES
    ('11111111-1111-4111-8111-111111111111', 'Alex Morgan', 'alex@example.test'),
    ('22222222-2222-4222-8222-222222222222', 'Sam Taylor', 'sam@example.test')
ON CONFLICT (id) DO NOTHING;

INSERT INTO workshop_booking.workshops
    (id, title, description, starts_at, duration_minutes, capacity)
VALUES
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Print your first linocut',
     'Design, carve, and print a two-color postcard. Tools and materials included.',
     date_trunc('day', clock_timestamp() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' + interval '7 days 10 hours', 120, 8),
    ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Wheel throwing for beginners',
     'A small group introduction to centering clay and throwing a bowl.',
     date_trunc('day', clock_timestamp() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' + interval '8 days 14 hours', 90, 6),
    ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'Build a terrarium',
     'Create a miniature garden and learn how to keep it thriving.',
     date_trunc('day', clock_timestamp() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' + interval '10 days 11 hours', 75, 1)
ON CONFLICT (id) DO NOTHING;

COMMIT;
