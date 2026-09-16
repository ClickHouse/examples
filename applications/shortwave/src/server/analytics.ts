import { z } from "zod";
import type { Analytics, AnalyticsFilter, Breakdown } from "../lib/types";
import { getClickHouse, getPostgres } from "./db";
import { getAccountId, getLink } from "./service";
import { runtimeEnvironment } from "./runtime";

const filterSchema = z
  .object({
    days: z.union([z.literal(7), z.literal(30), z.literal(90)]).default(30),
    linkId: z.string().uuid().optional(),
    campaign: z.string().max(200).optional(),
    tag: z.string().max(40).optional(),
  })
  .strict();

export async function getAnalytics(
  clerkUserId: string,
  input: AnalyticsFilter = {},
): Promise<Analytics> {
  const filter = filterSchema.parse(input);
  const accountId = await getAccountId(clerkUserId);
  if (filter.linkId) await getLink(clerkUserId, filter.linkId);
  const pending = await getPostgres().query(
    "SELECT count(*)::int AS count FROM click_outbox WHERE account_id = $1",
    [accountId],
  );
  const pendingEvents = pending.rows[0].count as number;
  const empty: Analytics = {
    status: "unavailable",
    message: null,
    totalClicks: 0,
    previousClicks: 0,
    daily: [],
    topLinks: [],
    referrers: [],
    countries: [],
    devices: [],
    browsers: [],
    campaigns: [],
    lastEventAt: null,
    pendingEvents,
  };
  try {
    const client = getClickHouse();
    const cdcDatabase =
      runtimeEnvironment("CLICKHOUSE_CDC_DATABASE") ||
      runtimeEnvironment("CLICKHOUSE_DATABASE") ||
      "default";
    if (!/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(cdcDatabase))
      throw new Error("Invalid CDC database name.");
    const now = new Date();
    // Complete UTC days plus today, and a preceding interval of the same length.
    const end = new Date(
      Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1),
    );
    const start = new Date(end.getTime() - filter.days * 86400_000);
    const previous = new Date(start.getTime() - filter.days * 86400_000);
    const timestamp = (date: Date) =>
      date.toISOString().replace("T", " ").replace("Z", "");
    const params = {
      account: accountId,
      start: timestamp(start),
      end: timestamp(end),
      previous: timestamp(previous),
      link: filter.linkId ?? "",
      campaign: filter.campaign ?? "",
      tag: filter.tag ?? "",
    };
    // Filter by current replicated tags. FINAL is essential before replacement merges complete.
    // Membership avoids multiplying a click when a link has more than one matching tag.
    const scope = `account_id = {account:UUID} AND is_demo = 0
      ${filter.linkId ? "AND link_id = {link:UUID}" : ""}
      ${filter.campaign !== undefined ? "AND utm_campaign = {campaign:String}" : ""}
      ${
        filter.tag
          ? `AND link_id IN (SELECT id FROM ${cdcDatabase}.cdc_links FINAL
        WHERE account_id = {account:UUID} AND _peerdb_is_deleted = 0 AND has(tags, {tag:String}))`
          : ""
      }`;
    const current = `${scope} AND occurred_at >= {start:DateTime64(3)} AND occurred_at < {end:DateTime64(3)}`;
    const query = async <T>(sql: string): Promise<T[]> => {
      const result = await client.query({
        query: sql,
        query_params: params,
        format: "JSONEachRow",
      });
      return result.json<T>();
    };
    const breakdown = async (
      column:
        "referrer_domain" | "country" | "device" | "browser" | "utm_campaign",
    ): Promise<Breakdown[]> => {
      const rows = await query<{
        name: string;
        clicks: string;
      }>(`SELECT ${column} AS name, uniqExact(event_id) AS clicks
        FROM click_events WHERE ${current} GROUP BY name ORDER BY clicks DESC LIMIT 10`);
      return rows.map((row) => ({
        name:
          row.name ||
          (column === "referrer_domain" ? "Direct / unknown" : "Not set"),
        clicks: Number(row.clicks),
      }));
    };
    const tagMetadataCurrent = filter.tag
      ? Promise.all([
          getPostgres().query(
            "SELECT id, revision FROM links WHERE account_id = $1",
            [accountId],
          ),
          query<{ id: string; revision: string }>(`SELECT
            toString(id) AS id, toString(revision) AS revision
            FROM ${cdcDatabase}.cdc_links FINAL
            WHERE account_id = {account:UUID} AND _peerdb_is_deleted = 0`),
        ]).then(([postgresLinks, cdcLinks]) => {
          if (postgresLinks.rows.length !== cdcLinks.length) return false;
          const cdcRevisions = new Map(
            cdcLinks.map((link) => [link.id, link.revision]),
          );
          return postgresLinks.rows.every(
            (link) =>
              cdcRevisions.get(link.id) === String(link.revision),
          );
        })
      : Promise.resolve(true);
    const [
      totals,
      daily,
      top,
      referrers,
      countries,
      devices,
      browsers,
      campaigns,
      tagsCurrent,
    ] = await Promise.all([
      query<{ total: string; previous: string; last: string | null }>(`SELECT
        uniqExactIf(event_id, occurred_at >= {start:DateTime64(3)}) AS total,
        uniqExactIf(event_id, occurred_at < {start:DateTime64(3)}) AS previous,
        maxOrNull(occurred_at) AS last FROM click_events WHERE ${scope}
        AND occurred_at >= {previous:DateTime64(3)} AND occurred_at < {end:DateTime64(3)}`),
      query<{
        date: string;
        clicks: string;
      }>(`SELECT toString(toDate(occurred_at, 'UTC')) AS date, uniqExact(event_id) AS clicks
        FROM click_events WHERE ${current} GROUP BY date ORDER BY date`),
      query<{
        link_id: string;
        clicks: string;
      }>(`SELECT link_id, uniqExact(event_id) AS clicks
        FROM click_events WHERE ${current} GROUP BY link_id ORDER BY clicks DESC LIMIT 10`),
      breakdown("referrer_domain"),
      breakdown("country"),
      breakdown("device"),
      breakdown("browser"),
      breakdown("utm_campaign"),
      tagMetadataCurrent,
    ]);
    const linkIds = top.map((row) => row.link_id);
    const metadata = linkIds.length
      ? await getPostgres().query(
          "SELECT id, title, slug FROM links WHERE account_id = $1 AND id = ANY($2::uuid[])",
          [accountId, linkIds],
        )
      : { rows: [] };
    const links = new Map(metadata.rows.map((row) => [row.id, row]));
    const dailyMap = new Map(
      daily.map((row) => [row.date, Number(row.clicks)]),
    );
    const totalClicks = Number(totals[0]?.total || 0);
    return {
      ...empty,
      status: pendingEvents
        ? "delayed"
        : !tagsCurrent
          ? "delayed"
          : totalClicks
            ? "ready"
            : "no-data",
      message: pendingEvents
        ? `${pendingEvents} recorded requests are waiting to appear in analytics.`
        : !tagsCurrent
          ? "Tags are still syncing to analytics. Refresh in a moment."
          : null,
      totalClicks,
      previousClicks: Number(totals[0]?.previous || 0),
      lastEventAt: totals[0]?.last
        ? `${totals[0].last.replace(" ", "T")}Z`
        : null,
      daily: Array.from({ length: filter.days }, (_, i) => {
        const date = new Date(start.getTime() + i * 86400_000)
          .toISOString()
          .slice(0, 10);
        return { date, clicks: dailyMap.get(date) ?? 0 };
      }),
      topLinks: top.map((row) => ({
        linkId: row.link_id,
        title: links.get(row.link_id)?.title || "Link",
        slug: links.get(row.link_id)?.slug || "",
        clicks: Number(row.clicks),
      })),
      referrers,
      countries,
      devices,
      browsers,
      campaigns,
    };
  } catch {
    return {
      ...empty,
      message: filter.tag
        ? "Analytics or replicated tag metadata is unavailable. Try again shortly."
        : "Analytics is temporarily unavailable. Your links still work.",
    };
  }
}
