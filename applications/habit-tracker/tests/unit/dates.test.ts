import assert from "node:assert/strict";
import test from "node:test";
import {
  addDays,
  appTimeZone,
  dayLabel,
  lastDays,
  todayIn,
} from "../../src/lib/dates";
import { checkInInput, habitName } from "../../src/lib/validation";

test("today follows the configured time zone", () => {
  const now = new Date("2026-03-01T03:00:00Z");
  assert.equal(todayIn("UTC", now), "2026-03-01");
  assert.equal(todayIn("America/Los_Angeles", now), "2026-02-28");
});

test("an unknown time zone fails fast", () => {
  assert.throws(
    () => appTimeZone({ APP_TIME_ZONE: "Mars/Olympus" }),
    RangeError,
  );
  assert.equal(appTimeZone({}), "UTC");
});

test("day arithmetic crosses month and leap-year boundaries", () => {
  assert.equal(addDays("2028-02-28", 1), "2028-02-29");
  assert.equal(addDays("2026-03-01", -1), "2026-02-28");
  assert.deepEqual(lastDays("2026-01-02", 3), [
    "2025-12-31",
    "2026-01-01",
    "2026-01-02",
  ]);
  assert.equal(dayLabel("2026-10-01"), "Thu 1");
});

test("check-ins are limited to this week", () => {
  const input = checkInInput("2026-10-21");
  assert.ok(
    input.safeParse({ habitId: 1, day: "2026-10-21", done: true }).success,
  );
  assert.ok(
    input.safeParse({ habitId: 1, day: "2026-10-15", done: false }).success,
  );
  assert.ok(
    !input.safeParse({ habitId: 1, day: "2026-10-14", done: true }).success,
  );
  assert.ok(
    !input.safeParse({ habitId: 1, day: "2026-10-22", done: true }).success,
  );
  assert.ok(
    !input.safeParse({ habitId: 1, day: "21/10/2026", done: true }).success,
  );
});

test("habit names are trimmed and bounded", () => {
  assert.equal(habitName.parse("  Stretch  "), "Stretch");
  assert.ok(!habitName.safeParse("   ").success);
  assert.ok(!habitName.safeParse("x".repeat(61)).success);
});
