// Days are plain 'YYYY-MM-DD' strings, matching the Postgres `date` column.
// "Today" comes from one configured time zone (APP_TIME_ZONE).

export function appTimeZone(
  env: Record<string, string | undefined> = process.env,
): string {
  const timeZone = env.APP_TIME_ZONE || "UTC";
  new Intl.DateTimeFormat("en-US", { timeZone }); // throws RangeError if invalid
  return timeZone;
}

export function todayIn(timeZone: string, now: Date = new Date()): string {
  // en-CA formats dates as YYYY-MM-DD.
  return new Intl.DateTimeFormat("en-CA", { timeZone }).format(now);
}

export function addDays(day: string, delta: number): string {
  const d = new Date(`${day}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + delta);
  return d.toISOString().slice(0, 10);
}

/** The last `count` days ending with `today`, oldest first. */
export function lastDays(today: string, count: number): string[] {
  return Array.from({ length: count }, (_, i) => addDays(today, i - count + 1));
}

/** "Thu 15" */
export function dayLabel(day: string): string {
  const weekday = new Date(`${day}T00:00:00Z`).toLocaleDateString("en-US", {
    weekday: "short",
    timeZone: "UTC",
  });
  return `${weekday} ${Number(day.slice(8))}`;
}
