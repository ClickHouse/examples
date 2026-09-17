-- Run as workshop_booking_owner (Alembic applies this after the initial DDL).
-- No blanket default privileges: review runtime access in each new migration.
REVOKE ALL ON ALL TABLES IN SCHEMA workshop_booking FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA workshop_booking FROM workshop_booking_app;
GRANT USAGE ON SCHEMA workshop_booking TO workshop_booking_app;
GRANT SELECT ON workshop_booking.workshops, workshop_booking.attendees,
    workshop_booking.bookings TO workshop_booking_app;
GRANT INSERT ON workshop_booking.bookings TO workshop_booking_app;
GRANT UPDATE (cancelled_at) ON workshop_booking.bookings TO workshop_booking_app;

-- SELECT ... FOR UPDATE needs UPDATE privilege on at least one column.
-- Grant only id; the application never changes it. Capacity, workshop details,
-- attendee details, booking identity, DELETE, and schema DDL remain restricted.
GRANT UPDATE (id) ON workshop_booking.workshops TO workshop_booking_app;
