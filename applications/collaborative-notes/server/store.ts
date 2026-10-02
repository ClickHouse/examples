import { createHash } from "node:crypto";
import type pg from "pg";
import {
  allowedDocument,
  NOTES,
  type Storage,
  type StoreReceipt,
} from "../shared/spec.js";
import { mergeState, validateState } from "./binary.js";
type Row = { state: Buffer; revision: number; stored_at: Date };
export class PostgresStorage implements Storage {
  constructor(private readonly pool: pg.Pool) {}
  async verify(): Promise<void> {
    const result = await this.pool.query(
      "SELECT id, state FROM notes.documents ORDER BY id",
    );
    if (
      result.rows.length !== NOTES.length ||
      result.rows.some((row) => !allowedDocument(row.id))
    ) {
      throw new Error("Run the reviewed migration and seed before starting.");
    }
    for (const row of result.rows) validateState(row.state);
  }
  async load(name: string): Promise<Uint8Array> {
    if (!allowedDocument(name)) throw new Error("Unknown note.");
    const result = await this.pool.query<Row>(
      "SELECT state, revision, stored_at FROM notes.documents WHERE id = $1",
      [name],
    );
    if (result.rows.length !== 1) throw new Error("Seeded note missing.");
    validateState(result.rows[0]!.state);
    return result.rows[0]!.state;
  }
  async store(name: string, captured: Uint8Array): Promise<StoreReceipt> {
    if (!allowedDocument(name)) throw new Error("Unknown note.");
    // Copy before awaiting: the receipt identifies this immutable captured update.
    const incoming = Buffer.from(captured);
    validateState(incoming);
    const capturedHash = createHash("sha256").update(incoming).digest("hex");
    const client = await this.pool.connect();
    let discard = false;
    try {
      await client.query("BEGIN");
      const result = await client.query<Row>(
        "SELECT state, revision, stored_at FROM notes.documents WHERE id = $1 FOR UPDATE",
        [name],
      );
      let row = result.rows[0];
      if (!row) throw new Error("Seeded note missing.");
      const merged = Buffer.from(mergeState(row.state, incoming));
      if (!merged.equals(row.state)) {
        if (row.revision >= 1000000000)
          throw new Error("Snapshot revision limit reached.");
        const changed = await client.query<Row>(
          "UPDATE notes.documents SET state = $1, revision = revision + 1, stored_at = clock_timestamp() WHERE id = $2 RETURNING state, revision, stored_at",
          [merged, name],
        );
        row = changed.rows[0]!;
      }
      await client.query("COMMIT");
      return {
        document: name,
        revision: row.revision,
        storedAt: row.stored_at.toISOString(),
        capturedHash,
      };
    } catch (error) {
      await client.query("ROLLBACK").catch(() => {
        discard = true;
      });
      throw error;
    } finally {
      client.release(discard);
    }
  }
}
