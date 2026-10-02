import { migrate } from "drizzle-orm/postgres-js/migrator";
import { drizzle } from "drizzle-orm/postgres-js";
import { connect } from "../src/lib/server/connection";
const client = connect(process.env.MIGRATION_DATABASE_URL);
try {
  await migrate(drizzle(client), {
    migrationsFolder: "./drizzle",
    migrationsSchema: "reading_migrations",
  });
  console.log("Migrations applied");
} finally {
  await client.end();
}
