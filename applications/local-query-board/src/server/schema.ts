import { pgSchema, uuid, text, integer } from "drizzle-orm/pg-core";
const board = pgSchema("planning");
export const projects = board.table("projects", {
  id: uuid().primaryKey(),
  board_id: text().notNull(),
  name: text().notNull(),
  color: text().notNull(),
});
export const tasks = board.table("tasks", {
  id: uuid().primaryKey(),
  board_id: text().notNull(),
  project_id: uuid().notNull(),
  title: text().notNull(),
  status: text().notNull(),
  priority: text().notNull(),
  revision: integer().notNull(),
});
