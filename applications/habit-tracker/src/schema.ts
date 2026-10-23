import { sql } from "drizzle-orm";
import {
  check,
  date,
  index,
  integer,
  pgSchema,
  primaryKey,
  text,
  timestamp,
} from "drizzle-orm/pg-core";

export const habitTracker = pgSchema("habit_tracker");

export const users = habitTracker.table("users", {
  id: integer().primaryKey().generatedAlwaysAsIdentity(),
  name: text().notNull(),
});

export const habits = habitTracker.table(
  "habits",
  {
    id: integer().primaryKey().generatedAlwaysAsIdentity(),
    userId: integer("user_id")
      .notNull()
      .references(() => users.id),
    name: text().notNull(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    archivedAt: timestamp("archived_at", { withTimezone: true }),
  },
  (t) => [
    check("habits_name_length", sql`char_length(${t.name}) between 1 and 60`),
    index("habits_active_by_user")
      .on(t.userId)
      .where(sql`${t.archivedAt} is null`),
  ],
);

export const checkIns = habitTracker.table(
  "check_ins",
  {
    habitId: integer("habit_id")
      .notNull()
      .references(() => habits.id, { onDelete: "cascade" }),
    day: date({ mode: "string" }).notNull(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  // One check-in per habit per day. The primary key is the UNIQUE (habit_id, day)
  // constraint that makes double clicks, retries and races harmless.
  (t) => [primaryKey({ columns: [t.habitId, t.day] })],
);
