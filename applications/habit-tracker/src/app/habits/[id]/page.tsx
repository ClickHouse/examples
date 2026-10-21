import { BigStat, Container, Text, Title } from "@clickhouse/click-ui";
import { notFound } from "next/navigation";
import { connection } from "next/server";
import { AppLink } from "@/components/app-link";
import { getDb } from "@/db";
import { appTimeZone, todayIn } from "@/lib/dates";
import { DEMO_USER_ID, habitHistory } from "@/lib/habits";
import { habitId } from "@/lib/validation";

const HISTORY_DAYS = 91; // 13 full weeks

export default async function HabitPage({ params }: PageProps<"/habits/[id]">) {
  await connection();
  const id = habitId.safeParse((await params).id);
  if (!id.success) notFound();
  const today = todayIn(appTimeZone());
  const habit = await habitHistory(
    getDb(),
    DEMO_USER_ID,
    id.data,
    today,
    HISTORY_DAYS,
  );
  if (!habit) notFound();
  const total = habit.days.filter((d) => d.done).length;

  return (
    <Container orientation="vertical" gap="xl">
      <AppLink href="/">← All habits</AppLink>
      <Title type="h1" size="xl">
        {habit.name}
      </Title>
      <Container gap="md">
        <BigStat label="Current streak" title={habit.streak.current} />
        <BigStat label="Longest streak" title={habit.streak.longest} />
        <BigStat label={`Check-ins, last ${HISTORY_DAYS} days`} title={total} />
      </Container>
      <div
        className="heatmap"
        aria-label={`${habit.name}, last ${HISTORY_DAYS} days`}
      >
        {habit.days.map((d) => (
          <span
            key={d.day}
            data-done={d.done}
            title={`${d.day}${d.done ? ": done" : ""}`}
          />
        ))}
      </div>
      <Text color="muted" size="sm">
        Each square is one day, oldest first, one column per week.
      </Text>
    </Container>
  );
}
