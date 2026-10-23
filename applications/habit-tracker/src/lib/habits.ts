import { and, asc, eq, gte, inArray, isNull, sql } from "drizzle-orm";
import type { Db } from "../db";
import { checkIns, habits } from "../schema";
import { addDays } from "./dates";

/** No auth in this example: every request acts as the user seeded by sql/03_seed.sql. */
export const DEMO_USER_ID = 1;

export type Streak = { current: number; longest: number };

const ownedActiveHabit = (userId: number, habitId: number) =>
  and(
    eq(habits.id, habitId),
    eq(habits.userId, userId),
    isNull(habits.archivedAt),
  );

export async function createHabit(db: Db, userId: number, name: string) {
  const [habit] = await db
    .insert(habits)
    .values({ userId, name })
    .returning({ id: habits.id });
  return habit.id;
}

export async function archiveHabit(db: Db, userId: number, habitId: number) {
  await db
    .update(habits)
    .set({ archivedAt: sql`now()` })
    .where(ownedActiveHabit(userId, habitId));
}

/**
 * Sets the check-in for one habit and day to the state the user clicked.
 * The request carries the desired state rather than "toggle", so a double
 * click or a retried request repeats the same write instead of undoing it.
 */
export async function setCheckIn(
  db: Db,
  userId: number,
  habitId: number,
  day: string,
  done: boolean,
) {
  if (done) {
    // INSERT ... SELECT only inserts for a habit this user owns. The (habit_id, day)
    // primary key turns any repeat or concurrent insert into a no-op.
    await db
      .insert(checkIns)
      .select(
        db
          .select({
            habitId: habits.id,
            day: sql`${day}::date`.as("day"),
            createdAt: sql`now()`.as("created_at"),
          })
          .from(habits)
          .where(ownedActiveHabit(userId, habitId)),
      )
      .onConflictDoNothing();
  } else {
    await db
      .delete(checkIns)
      .where(
        and(
          eq(checkIns.day, day),
          inArray(
            checkIns.habitId,
            db
              .select({ id: habits.id })
              .from(habits)
              .where(ownedActiveHabit(userId, habitId)),
          ),
        ),
      );
  }
}

/**
 * Current and longest streak per habit, computed in Postgres with the
 * gaps-and-islands pattern: consecutive days minus their row number give the
 * same value, so each run of days groups together. A streak is current if its
 * last day is today or yesterday (today's check-in may still be to come).
 */
export async function streaks(
  db: Db,
  userId: number,
  today: string,
): Promise<Map<number, Streak>> {
  const { rows } = await db.execute<{
    habit_id: number;
    current: number;
    longest: number;
  }>(sql`
    with islands as (
      select c.habit_id, c.day,
             c.day - (row_number() over (partition by c.habit_id order by c.day))::int as island
      from ${checkIns} c
      join ${habits} h on h.id = c.habit_id
      where h.user_id = ${userId} and h.archived_at is null
    ),
    runs as (
      select habit_id, max(day) as last_day, count(*)::int as length
      from islands
      group by habit_id, island
    )
    select habit_id,
           coalesce(max(length) filter (where last_day >= ${today}::date - 1), 0)::int as current,
           max(length)::int as longest
    from runs
    group by habit_id
  `);
  return new Map(
    rows.map((r) => [r.habit_id, { current: r.current, longest: r.longest }]),
  );
}

/** Active habits with their check-ins since `firstDay` and their streaks. */
export async function listHabits(
  db: Db,
  userId: number,
  today: string,
  firstDay: string,
) {
  const [active, recent, streakByHabit] = await Promise.all([
    db
      .select({ id: habits.id, name: habits.name })
      .from(habits)
      .where(and(eq(habits.userId, userId), isNull(habits.archivedAt)))
      .orderBy(asc(habits.createdAt), asc(habits.id)),
    db
      .select({ habitId: checkIns.habitId, day: checkIns.day })
      .from(checkIns)
      .innerJoin(habits, eq(habits.id, checkIns.habitId))
      .where(
        and(
          eq(habits.userId, userId),
          isNull(habits.archivedAt),
          gte(checkIns.day, firstDay),
        ),
      ),
    streaks(db, userId, today),
  ]);
  return active.map((habit) => ({
    ...habit,
    days: new Set(
      recent.filter((c) => c.habitId === habit.id).map((c) => c.day),
    ),
    streak: streakByHabit.get(habit.id) ?? { current: 0, longest: 0 },
  }));
}

/** One habit's last `count` days, filled with generate_series so missed days appear too. */
export async function habitHistory(
  db: Db,
  userId: number,
  habitId: number,
  today: string,
  count: number,
) {
  const [habit] = await db
    .select({ id: habits.id, name: habits.name })
    .from(habits)
    .where(ownedActiveHabit(userId, habitId));
  if (!habit) return null;
  const [{ rows: days }, streakByHabit] = await Promise.all([
    db.execute<{ day: string; done: boolean }>(sql`
      select d::date::text as day, c.habit_id is not null as done
      from generate_series(${addDays(today, 1 - count)}::date, ${today}::date, interval '1 day') d
      left join ${checkIns} c on c.habit_id = ${habitId} and c.day = d::date
      order by d
    `),
    streaks(db, userId, today),
  ]);
  return {
    ...habit,
    days,
    streak: streakByHabit.get(habitId) ?? { current: 0, longest: 0 },
  };
}
