import postgres from "postgres";
import { readFileSync } from "node:fs";
export function connect(
  url = process.env.DATABASE_URL,
  caPath = process.env.DATABASE_CA_PATH,
) {
  if (!url || !caPath)
    throw new Error("DATABASE_URL and DATABASE_CA_PATH are required");
  const parsed = new URL(url);
  if (parsed.protocol !== "postgresql:" || parsed.search)
    throw new Error("Use a plain postgresql URL without query parameters");
  return postgres(url, {
    max: 5,
    connect_timeout: 10,
    idle_timeout: 20,
    ssl: {
      ca: readFileSync(caPath, "utf8"),
      rejectUnauthorized: true,
      servername: parsed.hostname,
    },
  });
}
