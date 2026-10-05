import { Temporal } from "temporal-polyfill";
import { getPool } from "./db.js";
import {
  ZONE,
  type Appointment,
  type Update,
  type Day,
} from "../shared/contract.js";
export class BookingError extends Error {
  constructor(
    public status: 400 | 404 | 409,
    message: string,
  ) {
    super(message);
  }
}
interface Row {
  id: number;
  bay_id: number;
  service_id: number;
  customer: string;
  note: string;
  starts_at: Date;
  ends_at: Date;
  duration_minutes: number;
  revision: number;
  service_name: string;
}
const map = (r: Row): Appointment => ({
  id: r.id,
  bayId: r.bay_id,
  serviceId: r.service_id,
  customer: r.customer,
  note: r.note,
  startsAt: r.starts_at.toISOString(),
  endsAt: r.ends_at.toISOString(),
  durationMinutes: r.duration_minutes,
  revision: r.revision,
  serviceName: r.service_name,
});
export function bounds(date: string) {
  const day = Temporal.PlainDate.from(date);
  const start = day.toZonedDateTime({ timeZone: ZONE, plainTime: "00:00" });
  return [
    start.toInstant().toString(),
    start.add({ days: 1 }).toInstant().toString(),
  ];
}
export async function readDay(date: string): Promise<Day> {
  let range: string[];
  try {
    range = bounds(date);
  } catch {
    throw new BookingError(400, "Choose a valid workshop date.");
  }
  const client = await getPool().connect();
  try {
    await client.query("BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY");
    const bays = (
      await client.query<{ id: number; name: string }>(
        "SELECT id, name FROM bays ORDER BY id",
      )
    ).rows;
    const services = (
      await client.query<{ id: number; name: string; durationMinutes: number }>(
        'SELECT id, name, duration_minutes AS "durationMinutes" FROM services ORDER BY id',
      )
    ).rows;
    const appointments = (
      await client.query<Row>(
        `SELECT a.*, s.name AS service_name FROM appointments a JOIN services s ON s.id=a.service_id
      WHERE a.starts_at >= $1 AND a.starts_at < $2 ORDER BY a.starts_at,a.id`,
        range,
      )
    ).rows.map(map);
    const utilization = (
      await client.query<{
        bayId: number;
        name: string;
        bookedMinutes: number;
      }>(
        `SELECT b.id AS "bayId",b.name,
      COALESCE(SUM(EXTRACT(EPOCH FROM (a.ends_at-a.starts_at))/60),0)::INTEGER AS "bookedMinutes"
      FROM bays b LEFT JOIN appointments a ON a.bay_id=b.id AND a.starts_at >= $1 AND a.starts_at < $2 GROUP BY b.id,b.name ORDER BY b.id`,
        range,
      )
    ).rows;
    await client.query("COMMIT");
    return { date, zone: ZONE, bays, services, appointments, utilization };
  } catch (e) {
    await client.query("ROLLBACK");
    throw e;
  } finally {
    client.release();
  }
}
export async function updateAppointment(
  id: number,
  input: Update,
): Promise<Appointment> {
  const client = await getPool().connect();
  try {
    await client.query("BEGIN");
    const service = (
      await client.query<{ name: string; duration_minutes: number }>(
        "SELECT name,duration_minutes FROM services WHERE id=$1",
        [input.serviceId],
      )
    ).rows[0];
    if (!service)
      throw new BookingError(400, "Choose a known appointment type.");
    const start = Temporal.Instant.from(input.startsAt);
    const local = start.toZonedDateTimeISO(ZONE);
    const end = start.add({ minutes: service.duration_minutes });
    const wallEnd = end.toZonedDateTimeISO(ZONE);
    if (
      local.second ||
      local.millisecond ||
      local.microsecond ||
      local.nanosecond ||
      local.minute % 15 ||
      local.hour < 9 ||
      local.hour * 60 + local.minute + service.duration_minutes > 17 * 60 ||
      local.toPlainDate().toString() !== wallEnd.toPlainDate().toString()
    ) {
      throw new BookingError(
        400,
        "Use a quarter-hour start between 09:00 and 17:00 in Europe/London, with the whole appointment inside those hours.",
      );
    }
    const result = await client.query<Row>(
      `UPDATE appointments SET bay_id=$1, service_id=$2, customer=$3, note=$4,
      starts_at=$5, ends_at=$6, duration_minutes=$7, revision=revision+1
      WHERE id=$8 AND revision=$9 RETURNING *, $10::text AS service_name`,
      [
        input.bayId,
        input.serviceId,
        input.customer,
        input.note,
        start.toString(),
        end.toString(),
        service.duration_minutes,
        id,
        input.revision,
        service.name,
      ],
    );
    if (!result.rows.length) {
      const found = (
        await client.query("SELECT id FROM appointments WHERE id=$1", [id])
      ).rows.length;
      throw new BookingError(
        found ? 409 : 404,
        found
          ? "This appointment changed. Reload the saved calendar."
          : "This appointment does not exist.",
      );
    }
    await client.query("COMMIT");
    return map(result.rows[0]);
  } catch (e) {
    await client.query("ROLLBACK");
    if ((e as { code?: string }).code === "23P01")
      throw new BookingError(
        409,
        "That bay already has an appointment at this time. The saved appointment has been restored.",
      );
    if ((e as { code?: string }).code === "23503")
      throw new BookingError(400, "Choose a known bay and appointment type.");
    throw e;
  } finally {
    client.release();
  }
}
