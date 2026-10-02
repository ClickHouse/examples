import postgres from "postgres";
export function databaseOptions() {
  const required = (key: string): string => {
    const value = Deno.env.get(key);
    if (!value) throw new Error(`${key} is required`);
    return value;
  };
  const host = required("PGHOST");
  const port = Number(Deno.env.get("PGPORT") ?? "5432");
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error("Invalid PGPORT");
  return {
    host,
    port,
    database: required("PGDATABASE"),
    username: required("PGUSER"),
    password: required("PGPASSWORD"),
    ssl: {
      ca: Deno.readTextFileSync(required("PGSSLROOTCERT")),
      rejectUnauthorized: true,
      servername: host,
    },
    max: 3,
    connect_timeout: 15,
    idle_timeout: 20,
    fetch_types: false,
    connection: { application_name: "nearby-places", statement_timeout: 2000 },
  };
}
export function database() {
  return postgres(databaseOptions());
}
export type Database = ReturnType<typeof database>;
