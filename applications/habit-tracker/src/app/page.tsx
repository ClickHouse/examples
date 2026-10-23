import {
  Badge,
  Button,
  Container,
  Table,
  Text,
  Title,
} from "@clickhouse/click-ui";
import { connection } from "next/server";
import { AddHabitForm } from "@/components/add-habit-form";
import { AppLink } from "@/components/app-link";
import { CheckInBox } from "@/components/check-in-box";
import { getDb } from "@/db";
import { appTimeZone, lastDays, todayIn, dayLabel } from "@/lib/dates";
import { DEMO_USER_ID, listHabits } from "@/lib/habits";
import { EDITABLE_DAYS } from "@/lib/validation";
import { archiveHabitAction } from "./actions";

export default async function HabitsPage() {
  await connection(); // render per request: "today" and check-ins change
  const timeZone = appTimeZone();
  const today = todayIn(timeZone);
  const week = lastDays(today, EDITABLE_DAYS);
  const habits = await listHabits(getDb(), DEMO_USER_ID, today, week[0]);

  return (
    <Container orientation="vertical" gap="xl">
      <Container orientation="vertical" gap="xs">
        <Title type="h1" size="xl">
          Habit Tracker
        </Title>
        <Text color="muted">
          Today is {today} ({timeZone}). Tick a day to check in.
        </Text>
      </Container>
      <AddHabitForm />
      <Table
        headers={[
          { label: "Habit" },
          ...week.map((day) => ({ label: dayLabel(day), width: "56px" })),
          { label: "Streak", width: "96px" },
          { label: "", width: "104px" },
        ]}
        rows={habits.map((habit) => ({
          id: habit.id,
          items: [
            {
              label: (
                <AppLink href={`/habits/${habit.id}`}>{habit.name}</AppLink>
              ),
            },
            ...week.map((day) => ({
              label: (
                <CheckInBox
                  habitId={habit.id}
                  day={day}
                  done={habit.days.has(day)}
                  label={`${habit.name} on ${day}`}
                />
              ),
            })),
            {
              label: (
                <Badge
                  text={`${habit.streak.current} day${habit.streak.current === 1 ? "" : "s"}`}
                  state={habit.streak.current > 0 ? "success" : "neutral"}
                />
              ),
            },
            {
              label: (
                <form action={archiveHabitAction}>
                  <input type="hidden" name="habitId" value={habit.id} />
                  <Button htmlType="submit" type="secondary" label="Archive" />
                </form>
              ),
            },
          ],
        }))}
        noDataMessage="No habits yet. Add one above."
      />
    </Container>
  );
}
