import { createCollection } from "@tanstack/db";
import { electricCollectionOptions } from "@tanstack/electric-db-collection";
import { taskSchema, projectSchema } from "../shared";
export const tasks = createCollection(
  electricCollectionOptions({
    id: "studio-tasks",
    syncMode: "eager",
    schema: taskSchema,
    getKey: (row) => row.id,
    shapeOptions: {
      url: new URL("/api/shapes/tasks", window.location.origin).toString(),
    },
  }),
);
export const projects = createCollection(
  electricCollectionOptions({
    id: "studio-projects",
    syncMode: "eager",
    schema: projectSchema,
    getKey: (row) => row.id,
    shapeOptions: {
      url: new URL("/api/shapes/projects", window.location.origin).toString(),
    },
  }),
);
