GRANT SELECT ON
  appointment_calendar.bays,
  appointment_calendar.services,
  appointment_calendar.appointments
TO appointment_calendar_app;

GRANT UPDATE (
  bay_id, service_id, customer, note,
  starts_at, ends_at, duration_minutes, revision
) ON appointment_calendar.appointments TO appointment_calendar_app;
