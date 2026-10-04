import {
  pgSchema,
  uuid,
  text,
  integer,
  customType,
  timestamp,
  primaryKey,
} from "drizzle-orm/pg-core";
import type { GraphDocument } from "../shared/types";
const topology = pgSchema("service_topology");
// Bun 1.4 serializes JSONB parameters itself. Drizzle's default JSONB string
// encoder would encode a JSON string a second time, so pass the object through.
const graphJson = customType<{
  data: GraphDocument;
  driverData: GraphDocument;
}>({
  dataType: () => "jsonb",
  toDriver: (value) => value,
  fromDriver: (value) => value,
});
export const graphs = topology.table("graphs", {
  id: uuid("id").primaryKey(),
  title: text("title").notNull(),
  revision: integer("revision").notNull(),
  document: graphJson("document").notNull(),
  updatedAt: timestamp("updated_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});
export const revisions = topology.table(
  "revisions",
  {
    graphId: uuid("graph_id")
      .notNull()
      .references(() => graphs.id),
    revision: integer("revision").notNull(),
    document: graphJson("document").notNull(),
    savedAt: timestamp("saved_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (table) => [primaryKey({ columns: [table.graphId, table.revision] })],
);
