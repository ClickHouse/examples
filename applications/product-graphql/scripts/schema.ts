import { printSchema } from "graphql";
import { schema } from "../src/server/graphql";
await Bun.write("schema.graphql", printSchema(schema) + "\n");
