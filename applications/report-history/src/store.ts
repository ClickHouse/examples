import { createClient, type ClickHouseClient } from '@clickhouse/client';
import 'dotenv/config';
import { chunks, prepareReport, withRetry, type PreparedReport, type ReportInput } from './report.ts';

export function connect(): ClickHouseClient {
  for (const name of ['CLICKHOUSE_URL', 'CLICKHOUSE_USER', 'CLICKHOUSE_PASSWORD']) {
    if (!process.env[name]) throw new Error(`Missing ${name}; run npm run cloud:setup first`);
  }
  if (!process.env.CLICKHOUSE_URL!.startsWith('https://')) throw new Error('This Cloud example requires HTTPS');
  return createClient({ url: process.env.CLICKHOUSE_URL, username: process.env.CLICKHOUSE_USER,
    password: process.env.CLICKHOUSE_PASSWORD, database: process.env.CLICKHOUSE_DATABASE ?? 'report_history',
    request_timeout: 60_000, max_open_connections: 3,
    clickhouse_settings: { async_insert: 0, select_sequential_consistency: '1', max_execution_time: 30,
      output_format_json_quote_64bit_integers: 1 } });
}

// FINAL deduplicates logical rows NOW; it does not wait for a background merge.
// Counting rows also hides a completion marker whose results are incomplete.
const visibleRuns = `
  SELECT r.* FROM report_runs AS r FINAL
  LEFT JOIN (
    SELECT tenant_id, run_id, count() AS actual_rows FROM report_results FINAL
    WHERE tenant_id = {tenant:String} GROUP BY tenant_id, run_id
  ) AS c USING (tenant_id, run_id)
  WHERE r.tenant_id = {tenant:String} AND r.expected_rows = coalesce(c.actual_rows, 0)`;

export class ReportStore {
  constructor(readonly client: ClickHouseClient) {}

  // Deliberately separate from the marker: interruption leaves unadvertised rows.
  async writeResults(report: PreparedReport): Promise<void> {
    for (const [index, batch] of chunks(report.results).entries()) {
      await withRetry(() => this.client.insert({ table: 'report_results', values: batch, format: 'JSONEachRow',
        clickhouse_settings: { insert_deduplicate: 1,
          insert_deduplication_token: `report-v1:${report.run.run_id}:results:${index}` } }));
    }
  }

  async writeCompletion(report: PreparedReport): Promise<void> {
    await withRetry(() => this.client.insert({ table: 'report_runs', values: [report.run], format: 'JSONEachRow',
      clickhouse_settings: { insert_deduplicate: 1,
        insert_deduplication_token: `report-v1:${report.run.run_id}:complete` } }));
  }

  async publish(input: ReportInput): Promise<string> {
    const report = prepareReport(input);
    await this.writeResults(report);
    await this.writeCompletion(report);
    return report.run.run_id;
  }

  async history(tenant: string) {
    const result = await this.client.query({ query: `SELECT * FROM (${visibleRuns}) ORDER BY completed_at DESC, run_id LIMIT 100`,
      query_params: { tenant }, format: 'JSONEachRow' });
    return result.json<PreparedReport['run']>();
  }

  async report(tenant: string, runId: string) {
    const result = await this.client.query({ query: `
      SELECT d.* FROM report_results AS d FINAL
      INNER JOIN (${visibleRuns}) AS r USING (tenant_id, run_id)
      WHERE d.tenant_id = {tenant:String} AND d.run_id = {runId:String}
      ORDER BY d.row_number LIMIT 100000`, query_params: { tenant, runId }, format: 'JSONEachRow' });
    return result.json<PreparedReport['results'][number]>();
  }

  async analytics(tenant: string) {
    const result = await this.client.query({ query: `
      SELECT toDate(r.completed_at) AS day, d.region, d.category,
        uniqExact(d.run_id) AS reports, count() AS result_rows,
        sum(d.revenue_cents) AS revenue_cents, sum(d.units) AS units
      FROM report_results AS d FINAL
      INNER JOIN (${visibleRuns}) AS r USING (tenant_id, run_id)
      WHERE d.tenant_id = {tenant:String}
      GROUP BY day, d.region, d.category ORDER BY day, d.region, d.category`,
      query_params: { tenant }, format: 'JSONEachRow' });
    return result.json<{ day: string; region: string; category: string; reports: string;
      result_rows: string; revenue_cents: string; units: string }>();
  }

  async status(tenant: string, runId: string, version: number,
    status: 'queued' | 'running' | 'completed' | 'failed', observedAt: string, detail = '') {
    if (!Number.isSafeInteger(version) || version < 1) throw new Error('version must be a positive safe integer');
    // A single workflow owner assigns monotonically increasing versions. No CAS/locking.
    const value = { tenant_id: tenant, run_id: runId, version, status,
      observed_at: new Date(observedAt).toISOString().replace('T', ' ').replace('Z', ''), detail };
    await withRetry(() => this.client.insert({ table: 'run_status', values: [value], format: 'JSONEachRow' }));
  }

  async currentStatus(tenant: string, runId: string) {
    const result = await this.client.query({ query: `SELECT run_id, version, status, detail FROM run_status FINAL
      WHERE tenant_id = {tenant:String} AND run_id = {runId:String}`,
      query_params: { tenant, runId }, format: 'JSONEachRow' });
    return result.json<{ run_id: string; version: string; status: string; detail: string }>();
  }
}
