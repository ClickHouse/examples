import "dotenv/config";
import { defineConfig } from "prisma/config";

export default defineConfig({
  schema: "prisma/schema.prisma",
  migrations: { path: "prisma/migrations" },
  // generate/build do not need a database credential; migrate deploy does.
  datasource: { url: process.env.MIGRATION_DATABASE_URL ?? "" },
});
