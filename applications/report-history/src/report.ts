import { createHash } from 'node:crypto';

export interface ResultRow {
  region: string;
  category: string;
  revenue_cents: number;
  units: number;
}
export interface ReportInput {
  tenant_id: string;
  completed_at: string;
  report_type: string;
  source_uri: string;
  artifact_uri: string;
  rows: ResultRow[];
}
export interface PreparedReport {
  run: {
    tenant_id: string; run_id: string; completed_at: string; report_type: string;
    source_uri: string; artifact_uri: string; expected_rows: number; summary_json: string;
  };
  results: (ResultRow & { tenant_id: string; run_id: string; completed_at: string; row_number: number })[];
}

// Canonical field order means object property order cannot accidentally change identity.
// A changed payload is a NEW immutable run, never an overwrite under the old run ID.
export function prepareReport(input: ReportInput): PreparedReport {
  if (!input.tenant_id || !input.report_type || !input.source_uri || !input.artifact_uri) {
    throw new Error('tenant_id, report_type, source_uri and artifact_uri are required');
  }
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(input.completed_at) ||
      new Date(input.completed_at).toISOString() !== input.completed_at) {
    throw new Error('completed_at must be an exact UTC ISO timestamp, preserved across retries');
  }
  if (input.rows.length > 100_000) throw new Error('Demo supports at most 100,000 result rows per report');
  const rows = input.rows.map((row) => {
    if (!row.region || !row.category || !Number.isSafeInteger(row.revenue_cents) ||
        !Number.isSafeInteger(row.units) || row.units < 0 || row.units > 4_294_967_295) {
      throw new Error('Invalid result: use nonempty dimensions, integer cents and UInt32 units');
    }
    return { region: row.region, category: row.category, revenue_cents: row.revenue_cents, units: row.units };
  });
  const exactTotal = rows.reduce((sum, row) => sum + BigInt(row.revenue_cents), 0n);
  if (exactTotal > BigInt(Number.MAX_SAFE_INTEGER) || exactTotal < BigInt(Number.MIN_SAFE_INTEGER)) {
    throw new Error('Report total exceeds JavaScript safe integer range');
  }
  const total = Number(exactTotal);
  const canonical = { schema_version: 1, tenant_id: input.tenant_id, completed_at: input.completed_at,
    report_type: input.report_type, source_uri: input.source_uri, artifact_uri: input.artifact_uri, rows };
  const run_id = createHash('sha256').update(JSON.stringify(canonical)).digest('hex');
  const completed_at = input.completed_at.replace('T', ' ').replace('Z', '');
  return {
    run: { tenant_id: input.tenant_id, run_id, completed_at, report_type: input.report_type,
      source_uri: input.source_uri, artifact_uri: input.artifact_uri, expected_rows: rows.length,
      summary_json: JSON.stringify({ revenue_cents: total, regions: new Set(rows.map((row) => row.region)).size }) },
    results: rows.map((row, row_number) => ({ ...row, tenant_id: input.tenant_id, run_id,
      completed_at, row_number })),
  };
}

export function chunks<T>(rows: T[], size = 1000): T[][] {
  if (!Number.isSafeInteger(size) || size < 1) throw new Error('Chunk size must be a positive integer');
  return Array.from({ length: Math.ceil(rows.length / size) }, (_, index) => rows.slice(index * size, (index + 1) * size));
}

export function isTransient(error: unknown): boolean {
  const value = error as { code?: string; cause?: unknown; message?: string };
  // @clickhouse/client 1.23.1 emits this exact unclassified request_timeout error.
  return (error instanceof Error && value.code === undefined && value.message === 'Timeout error.') ||
    ['ECONNRESET', 'ETIMEDOUT', 'ECONNREFUSED', 'EPIPE', 'UND_ERR_SOCKET', 'UND_ERR_CONNECT_TIMEOUT']
    .includes(String(value?.code)) || (value?.cause !== undefined && isTransient(value.cause));
}

export async function withRetry<T>(operation: () => Promise<T>, options: {
  attempts?: number; sleep?: (milliseconds: number) => Promise<unknown>;
} = {}): Promise<T> {
  const attempts = options.attempts ?? 4;
  const sleep = options.sleep ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));
  for (let attempt = 0; ; attempt++) {
    try { return await operation(); }
    catch (error) {
      if (attempt + 1 >= attempts || !isTransient(error)) throw error;
      await sleep(250 * 2 ** attempt + Math.floor(Math.random() * 100));
    }
  }
}
