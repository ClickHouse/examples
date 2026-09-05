import { readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { parse } from 'csv-parse/sync';
import { prepareReport, type ReportInput, type ResultRow } from './report.ts';

export function generateReport(sourcePath: string, artifactPath: string, input: {
  tenant_id: string; completed_at: string; report_type: string;
}): ReportInput {
  // This deterministic generator deliberately needs no LLM key or external service.
  const records = parse(readFileSync(sourcePath, 'utf8'), { columns: true, skip_empty_lines: true }) as
    { region: string; category: string; revenue_cents: string; units: string }[];
  const rows: ResultRow[] = records.map((row) => {
    if (!/^-?\d+$/.test(row.revenue_cents) || !/^\d+$/.test(row.units)) {
      throw new Error('CSV revenue_cents and units must contain integer values, not blanks or decimals');
    }
    return { region: row.region, category: row.category,
      revenue_cents: Number(row.revenue_cents), units: Number(row.units) };
  });
  const report: ReportInput = { ...input, source_uri: pathToFileURL(sourcePath).href,
    artifact_uri: pathToFileURL(artifactPath).href, rows };
  const prepared = prepareReport(report); // Validate before writing/publishing the artifact.
  const summary = JSON.parse(prepared.run.summary_json) as { revenue_cents: number; regions: number };
  const totals = new Map<string, bigint>();
  for (const row of rows) totals.set(row.region, (totals.get(row.region) ?? 0n) + BigInt(row.revenue_cents));
  writeFileSync(artifactPath, `# Sales report\n\nCompleted: ${input.completed_at}\n\n` +
    `Source: ${report.source_uri}\n\nRows: ${rows.length}\n\n` +
    `Revenue: ${summary.revenue_cents} cents across ${summary.regions} regions.\n\n` +
    '| Region | Revenue (cents) |\n| --- | ---: |\n' +
    [...totals].sort(([a], [b]) => a.localeCompare(b)).map(([region, cents]) =>
      `| ${region.replaceAll('|', '\\|').replaceAll('\n', ' ')} | ${cents} |`).join('\n') + '\n');
  return report;
}
