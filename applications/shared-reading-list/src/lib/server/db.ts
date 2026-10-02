import { drizzle } from "drizzle-orm/postgres-js";
import { connect } from "./connection";
import * as schema from "./schema";
export const client = connect();
export const db = drizzle(client, { schema });
