import { randomBytes } from "node:crypto";
import { connectDatabase } from "../src/server/database.ts";
import { passwordHash } from "../src/server/sessions.ts";
const pool = await connectDatabase(process.env.MIGRATION_DATABASE_URL);
for (const [id, email, workspace, name, password] of [
  [
    "40000000-0000-4000-8000-000000000001",
    "alice@example.test",
    "10000000-0000-4000-8000-000000000001",
    "Riverside Studio",
    "river-demo",
  ],
  [
    "40000000-0000-4000-8000-000000000002",
    "bob@example.test",
    "10000000-0000-4000-8000-000000000002",
    "Summit Team",
    "summit-demo",
  ],
]) {
  const salt = randomBytes(16).toString("hex");
  await pool.query(
    "INSERT INTO tracker_private.accounts(id,email,workspace_id,workspace_name,salt,password_hash) VALUES($1,$2,$3,$4,$5,$6)",
    [id, email, workspace, name, salt, passwordHash(password!, salt)],
  );
}
await pool.end();
console.log("Two synthetic demo accounts seeded with salted scrypt hashes.");
