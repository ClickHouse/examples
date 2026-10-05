import { initContract } from "@ts-rest/core";
import { z } from "zod";
export const ZONE = "Europe/London";
export const dayInput = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);
export const appointment = z.object({
  id: z.number().int(),
  bayId: z.number().int(),
  serviceId: z.number().int(),
  customer: z.string(),
  note: z.string(),
  startsAt: z.string().datetime(),
  endsAt: z.string().datetime(),
  durationMinutes: z.number().int(),
  revision: z.number().int(),
  serviceName: z.string(),
});
export const updateInput = z
  .object({
    revision: z.number().int().min(0).max(2147483646),
    bayId: z.number().int().min(1).max(3),
    serviceId: z.number().int().positive().max(2147483647),
    customer: z.string().trim().min(2).max(60),
    note: z.string().trim().max(300),
    startsAt: z.string().datetime({ offset: true }),
  })
  .strict();
const error = z.object({ message: z.string() });
export const dayOutput = z.object({
  date: dayInput,
  zone: z.literal(ZONE),
  bays: z.array(z.object({ id: z.number().int(), name: z.string() })),
  services: z.array(
    z.object({
      id: z.number().int(),
      name: z.string(),
      durationMinutes: z.number().int(),
    }),
  ),
  appointments: z.array(appointment),
  utilization: z.array(
    z.object({
      bayId: z.number().int(),
      name: z.string(),
      bookedMinutes: z.number().int().nonnegative(),
    }),
  ),
});
const c = initContract();
export const contract = c.router({
  day: {
    method: "GET",
    path: "/api/day",
    query: z.object({ date: dayInput }),
    responses: { 200: dayOutput, 400: error, 500: error },
  },
  update: {
    method: "PUT",
    path: "/api/appointments/:id",
    pathParams: z.object({
      id: z
        .string()
        .regex(/^[1-9]\d*$/)
        .refine((value) => Number(value) <= 2147483647),
    }),
    body: updateInput,
    responses: {
      200: appointment,
      400: error,
      404: error,
      409: error,
      500: error,
    },
  },
});
export type Appointment = z.infer<typeof appointment>;
export type Day = z.infer<typeof dayOutput>;
export type Update = z.infer<typeof updateInput>;
