BEGIN;

CREATE TABLE bays (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL
);

CREATE TABLE services (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  duration_minutes INTEGER NOT NULL CHECK (duration_minutes IN (30, 60, 90)),
  UNIQUE (id, duration_minutes)
);

CREATE TABLE appointments (
  id INTEGER PRIMARY KEY,
  bay_id INTEGER NOT NULL REFERENCES bays(id),
  service_id INTEGER NOT NULL,
  customer TEXT NOT NULL CHECK (length(customer) BETWEEN 2 AND 60),
  note TEXT NOT NULL DEFAULT '' CHECK (length(note) <= 300),
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ NOT NULL,
  duration_minutes INTEGER NOT NULL,
  revision INTEGER NOT NULL DEFAULT 0 CHECK (revision >= 0),
  FOREIGN KEY (service_id, duration_minutes) REFERENCES services(id, duration_minutes),
  CHECK (ends_at > starts_at AND EXTRACT(EPOCH FROM (ends_at - starts_at)) = duration_minutes * 60),
  EXCLUDE USING gist (
    bay_id public.gist_int4_ops WITH =,
    tstzrange(starts_at, ends_at, '[)') WITH &&
  )
);

INSERT INTO bays VALUES (1,'Inspection bay'),(2,'Service bay'),(3,'Detailing bay');
INSERT INTO services VALUES (1,'Safety inspection',30),(2,'Routine service',60),(3,'Deep clean',90);
INSERT INTO appointments (id, bay_id, service_id, customer, note, starts_at, ends_at, duration_minutes) VALUES
(1,1,1,'Morgan Reed','Check the brakes.','2026-10-05 09:00:00+01','2026-10-05 09:30:00+01',30),
(2,1,2,'Ellis Park','Routine annual service.','2026-10-05 10:00:00+01','2026-10-05 11:00:00+01',60),
(3,1,1,'Casey Lane','Inspect lights.','2026-10-05 13:00:00+01','2026-10-05 13:30:00+01',30),
(4,2,2,'Taylor Quinn','Check chain and gears.','2026-10-05 09:30:00+01','2026-10-05 10:30:00+01',60),
(5,2,2,'Robin Wells','Routine service.','2026-10-05 12:00:00+01','2026-10-05 13:00:00+01',60),
(6,3,3,'Avery Scott','Full clean.','2026-10-05 11:00:00+01','2026-10-05 12:30:00+01',90);
COMMIT;
