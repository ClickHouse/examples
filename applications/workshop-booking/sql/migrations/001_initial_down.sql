-- Destructive: this removes every booking, attendee, and workshop.
-- Alembic wraps this downgrade in a transaction and retains its version table.
DROP TABLE workshop_booking.bookings;
DROP TABLE workshop_booking.attendees;
DROP TABLE workshop_booking.workshops;
