"use server";

import { revalidatePath } from "next/cache";
import { getDb } from "@/db";
import { appTimeZone, todayIn } from "@/lib/dates";
import {
  archiveHabit,
  createHabit,
  DEMO_USER_ID,
  setCheckIn,
} from "@/lib/habits";
import { checkInInput, habitId, habitName } from "@/lib/validation";

export type FormState = { error?: string };

export async function createHabitAction(
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  const name = habitName.safeParse(formData.get("name"));
  if (!name.success) return { error: name.error.issues[0].message };
  await createHabit(getDb(), DEMO_USER_ID, name.data);
  revalidatePath("/");
  return {};
}

export async function archiveHabitAction(formData: FormData) {
  const id = habitId.parse(formData.get("habitId"));
  await archiveHabit(getDb(), DEMO_USER_ID, id);
  revalidatePath("/");
}

export async function setCheckInAction(input: {
  habitId: number;
  day: string;
  done: boolean;
}) {
  const today = todayIn(appTimeZone());
  const { habitId, day, done } = checkInInput(today).parse(input);
  await setCheckIn(getDb(), DEMO_USER_ID, habitId, day, done);
  revalidatePath("/");
}
