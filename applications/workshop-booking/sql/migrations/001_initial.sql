-- Alembic executes this file in its migration transaction after SET ROLE
-- workshop_booking_owner. Schema creation belongs to sql/bootstrap.sql.
CREATE TABLE workshop_booking.workshops (
    id uuid PRIMARY KEY,
    title varchar(160) NOT NULL,
    description text NOT NULL DEFAULT '',
    starts_at timestamptz NOT NULL,
    duration_minutes integer NOT NULL,
    capacity integer NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT workshops_title_not_blank CHECK (length(btrim(title)) > 0),
    CONSTRAINT workshops_capacity_positive CHECK (capacity BETWEEN 1 AND 10000),
    CONSTRAINT workshops_duration_positive CHECK (duration_minutes BETWEEN 1 AND 1440)
);

CREATE INDEX workshops_starts_at_id ON workshop_booking.workshops (starts_at, id);

CREATE TABLE workshop_booking.attendees (
    id uuid PRIMARY KEY,
    name varchar(120) NOT NULL,
    email varchar(254) NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT attendees_name_not_blank CHECK (length(btrim(name)) > 0),
    CONSTRAINT attendees_email_not_blank CHECK (length(btrim(email)) > 0)
);

CREATE TABLE workshop_booking.bookings (
    -- The caller generates this UUID once and reuses it after network failures.
    id uuid PRIMARY KEY,
    workshop_id uuid NOT NULL REFERENCES workshop_booking.workshops(id),
    attendee_id uuid NOT NULL REFERENCES workshop_booking.attendees(id),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    cancelled_at timestamptz,
    CONSTRAINT bookings_cancellation_after_creation CHECK (
        cancelled_at IS NULL OR cancelled_at >= created_at
    )
);

-- A cancelled row remains as a receipt. A new UUID may book again, but there
-- can never be two active bookings for the same attendee and workshop.
CREATE UNIQUE INDEX bookings_one_active_per_attendee_workshop
    ON workshop_booking.bookings (workshop_id, attendee_id)
    WHERE cancelled_at IS NULL;

CREATE INDEX bookings_attendee_id ON workshop_booking.bookings (attendee_id);
