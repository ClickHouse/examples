import { z } from "zod";
export const statuses = ["todo", "doing", "done"] as const;
export const priorities = ["low", "medium", "high"] as const;
export const taskSchema = z.object({
  id: z.string(),
  board_id: z.string(),
  project_id: z.string(),
  title: z.string(),
  status: z.enum(statuses),
  priority: z.enum(priorities),
  revision: z.number().int().positive(),
});
export const projectSchema = z.object({
  id: z.string(),
  board_id: z.string(),
  name: z.string(),
  color: z.string(),
});
export const createTaskSchema = z
  .object({
    title: z.string().trim().min(1).max(120),
    project_id: z.string().uuid(),
    priority: z.enum(priorities),
  })
  .strict();
export const updateTaskSchema = z
  .object({
    revision: z.number().int().positive().max(2147483647),
    status: z.enum(statuses),
    priority: z.enum(priorities),
  })
  .strict();
