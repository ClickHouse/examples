import { createPool } from "./database.js";
import { seedState } from "./binary.js";
import { NOTES } from "../shared/spec.js";
const pool = createPool();
try {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    for (const note of NOTES) {
      await client.query(
        "INSERT INTO notes.documents (id, title, state) VALUES ($1, $2, $3) ON CONFLICT (id) DO NOTHING",
        [
          note.id,
          note.title,
          Buffer.from(seedState(`${note.title}\nStart a shared note here.\n`)),
        ],
      );
    }
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
  console.log("Three seeded notes present; existing CRDT state preserved.");
} finally {
  await pool.end();
}
