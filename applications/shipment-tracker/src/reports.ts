import { Injectable, OnApplicationShutdown } from '@nestjs/common';
import { createClient } from '@clickhouse/client';
import { analyticalUrl, required } from './config.js';
import { reportRange } from './domain.js';
import type { ReportDto } from './dto.js';

const REPORT_LIMITS = {
  max_execution_time: 5, timeout_before_checking_execution_speed: 0,
  max_rows_to_read: '1000000', max_bytes_to_read: '100000000',
  max_result_rows: '186', result_overflow_mode: 'throw' as const,
  output_format_json_quote_64bit_integers: 1 as const,
};
interface ReportRow {
  eventDay: string; serviceLevel: string; toStatus: string;
  events: string; deliveredCount: string; totalDurationMs: string; maxDurationMs: string;
}
@Injectable()
export class ReportsService implements OnApplicationShutdown {
  // One shared pool. Client settings are defaults; individual requests can override them.
  private readonly client = createClient({
    url: analyticalUrl(required('CLICKHOUSE_URL')),
    username: required('CLICKHOUSE_USER'), password: required('CLICKHOUSE_PASSWORD'),
    database: 'default', application: 'shipment-tracker',
    max_open_connections: 2, request_timeout: 10_000,
    clickhouse_settings: REPORT_LIMITS,
  });
  constructor() {
    if (required('CLICKHOUSE_USER') !== 'shipments_reports') throw new Error('Restricted analytical login required');
  }
  async report(accountId: string, input: ReportDto) {
    const [from, to] = reportRange(input.from, input.to);
    const result = await this.client.query({
      query: `
        SELECT event_day AS eventDay, service_level AS serviceLevel, to_status AS toStatus,
          toString(count()) AS events,
          toString(countIf(to_status = 'delivered')) AS deliveredCount,
          toString(sumIf(duration_ms, to_status = 'delivered')) AS totalDurationMs,
          toString(maxIf(duration_ms, to_status = 'delivered')) AS maxDurationMs
        FROM default.cdc_shipment_events FINAL
        WHERE account_id = {account:UUID}
          AND event_day BETWEEN {from:Date32} AND {to:Date32}
          AND _peerdb_is_deleted = 0
        GROUP BY event_day, service_level, to_status
        ORDER BY event_day, service_level, to_status
        LIMIT 186
      `,
      query_params: { account: accountId, from, to }, format: 'JSONEachRow',
      clickhouse_settings: REPORT_LIMITS, abort_signal: AbortSignal.timeout(15_000),
    });
    try {
      const rows = await result.json<ReportRow>();
      return { accountId, from, to, consistency: 'eventual', operationalAuthority: 'postgres', rows };
    } finally { result.close(); }
  }
  async onApplicationShutdown(): Promise<void> { await this.client.close(); }
}
