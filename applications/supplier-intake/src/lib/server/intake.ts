import { createHash } from 'node:crypto';
import type { PoolClient } from 'pg';
import { database } from './database';
import { IntakeError, parseUpload } from './parsers';
import { mapRows, mappingSchema, type Mapping, type ReviewedRow } from '../mapping';
export class RevisionConflict extends IntakeError {}
export type Batch = {
  id: string;
  filename: string;
  format: string;
  headers: string[];
  supplier: string;
  mapping: Mapping | null;
  revision: number;
  status: 'uploaded' | 'reviewed' | 'promoted';
  created_at: string;
  row_count: number;
  invalid_count: number;
};
export async function transaction<T>(work: (client: PoolClient) => Promise<T>) {
  const client = await database().connect();
  try {
    await client.query('BEGIN');
    const result = await work(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}
export async function stageUpload(bytes: Buffer, filename: string) {
  const parsed = parseUpload(bytes, filename);
  const fingerprint = createHash('sha256').update(bytes).digest('hex');
  return transaction(async (client) => {
    const inserted = await client.query(
      'INSERT INTO intake.batches (fingerprint,filename,format,headers,row_count) VALUES ($1,$2,$3,$4::jsonb,$5) ON CONFLICT (fingerprint) DO NOTHING RETURNING id',
      [
        fingerprint,
        filename.replace(/[\x00-\x1f\/\\]/g, '_').slice(0, 120),
        parsed.format,
        JSON.stringify(parsed.headers),
        parsed.rows.length,
      ],
    );
    if (!inserted.rowCount)
      return {
        id: (
          await client.query('SELECT id FROM intake.batches WHERE fingerprint=$1', [
            fingerprint,
          ])
        ).rows[0].id as string,
        reused: true,
      };
    const id = inserted.rows[0].id as string;
    await client.query(
      'INSERT INTO intake.staging_rows (batch_id,row_number,raw_values) SELECT $1, ordinality + 1, value FROM jsonb_array_elements($2::jsonb) WITH ORDINALITY',
      [id, JSON.stringify(parsed.rows)],
    );
    return { id, reused: false };
  });
}
export async function getBatch(id: string) {
  return transaction(async (client) => {
    await client.query('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY');
    const batch = (
      await client.query<Batch>(
        "SELECT *, to_char(created_at AT TIME ZONE 'UTC','YYYY-MM-DD HH24:MI') AS created_at FROM intake.batches WHERE id=$1",
        [id],
      )
    ).rows[0];
    if (!batch) throw new IntakeError('Batch not found.');
    const rows = (
      await client.query<{
        row: number;
        raw: Record<string, string>;
        mapped: ReviewedRow['mapped'];
        errors: string[];
      }>(
        'SELECT row_number AS row, raw_values AS raw, mapped_values AS mapped, errors FROM intake.staging_rows WHERE batch_id=$1 ORDER BY row_number',
        [id],
      )
    ).rows;
    return { batch, rows };
  });
}
export async function reviewBatch(input: Mapping) {
  const mapping = mappingSchema.parse(input);
  return transaction(async (client) => {
    const batch = (
      await client.query<Batch>('SELECT * FROM intake.batches WHERE id=$1 FOR UPDATE', [
        mapping.batchId,
      ])
    ).rows[0];
    if (!batch) throw new IntakeError('Batch not found.');
    if (batch.status === 'promoted')
      throw new RevisionConflict('This batch has already been promoted.');
    if (batch.revision !== mapping.revision)
      throw new RevisionConflict(
        'This review changed in another tab. Reload before reviewing again.',
      );
    const columns = [mapping.sku, mapping.product, mapping.price, mapping.stock];
    if (columns.some((v) => !batch.headers.includes(v)) || new Set(columns).size !== 4)
      throw new IntakeError('Map each field to a different existing column.');
    const raw = (
      await client.query(
        'SELECT raw_values FROM intake.staging_rows WHERE batch_id=$1 ORDER BY row_number',
        [mapping.batchId],
      )
    ).rows.map((row) => row.raw_values as Record<string, string>);
    const rows = mapRows(raw, mapping);
    await client.query(
      'UPDATE intake.staging_rows AS s SET mapped_values=v.mapped, errors=v.errors FROM jsonb_to_recordset($2::jsonb) AS v(row integer,mapped jsonb,errors jsonb) WHERE s.batch_id=$1 AND s.row_number=v.row',
      [mapping.batchId, JSON.stringify(rows)],
    );
    const invalidCount = rows.filter((row) => row.errors.length).length;
    await client.query(
      "UPDATE intake.batches SET supplier=$2,mapping=$3::jsonb,status='reviewed',invalid_count=$4,revision=revision+1 WHERE id=$1",
      [mapping.batchId, mapping.supplier, JSON.stringify(mapping), invalidCount],
    );
    return { revision: batch.revision + 1, invalidCount };
  });
}
export async function promoteBatch(id: string, revision: number) {
  try {
    return await transaction(async (client) => {
      const batch = (
        await client.query<Batch>('SELECT * FROM intake.batches WHERE id=$1 FOR UPDATE', [
          id,
        ])
      ).rows[0];
      if (!batch) throw new IntakeError('Batch not found.');
      if (batch.status === 'promoted') return { count: batch.row_count, reused: true };
      if (batch.revision !== revision)
        throw new RevisionConflict('This review changed. Reload before promoting.');
      if (batch.status !== 'reviewed' || batch.invalid_count)
        throw new IntakeError(
          'Review every row successfully before promoting this batch.',
        );
      const invalid = await client.query(
        'SELECT 1 FROM intake.staging_rows WHERE batch_id=$1 AND (mapped_values IS NULL OR jsonb_array_length(errors)>0) LIMIT 1',
        [id],
      );
      if (invalid.rowCount)
        throw new IntakeError('Every row needs a valid reviewed mapping.');
      await client.query(
        "INSERT INTO intake.products (batch_id,row_number,supplier,supplier_key,sku,product,price_cents,stock) SELECT batch_id,row_number,$2,lower($2),mapped_values->>'sku',mapped_values->>'product',(mapped_values->>'cents')::integer,(mapped_values->>'stock')::integer FROM intake.staging_rows WHERE batch_id=$1 ORDER BY row_number",
        [id, batch.supplier],
      );
      await client.query(
        "UPDATE intake.batches SET status='promoted',revision=revision+1 WHERE id=$1",
        [id],
      );
      return { count: batch.row_count, reused: false };
    });
  } catch (error) {
    if ((error as { code?: string }).code === '23505')
      throw new IntakeError(
        'A supplier SKU already exists in the catalog. No rows were imported.',
      );
    throw error;
  }
}
export async function dashboard() {
  return transaction(async (client) => {
    await client.query('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY');
    const batches = (
      await client.query<Batch>(
        "SELECT *, to_char(created_at AT TIME ZONE 'UTC','YYYY-MM-DD HH24:MI') AS created_at FROM intake.batches ORDER BY intake.batches.created_at DESC,id LIMIT 12",
      )
    ).rows;
    const products = (
      await client.query<{
        supplier: string;
        sku: string;
        product: string;
        price_cents: number;
        stock: number;
      }>(
        'SELECT supplier,sku,product,price_cents,stock FROM intake.products ORDER BY supplier,sku LIMIT 200',
      )
    ).rows;
    const count = (
      await client.query('SELECT count(*)::integer AS total FROM intake.products')
    ).rows[0].total as number;
    return { batches, products, count };
  });
}
