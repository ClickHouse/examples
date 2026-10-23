import { z } from "zod";
import { addDays } from "./dates";

/** Check-ins can be changed for the visible week only: today and the six days before. */
export const EDITABLE_DAYS = 7;

export const habitName = z
  .string()
  .trim()
  .min(1, "Name the habit.")
  .max(60, "Keep it under 60 characters.");

export const habitId = z.coerce.number().int().positive();

export function checkInInput(today: string) {
  return z.object({
    habitId,
    day: z.iso
      .date()
      .refine(
        (day) => day <= today && day > addDays(today, -EDITABLE_DAYS),
        "Only this week's days can be changed.",
      ),
    done: z.boolean(),
  });
}
