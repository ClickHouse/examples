import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import {
  Activity,
  ArrowUpRight,
  BarChart3,
  Globe2,
  Link2,
  RefreshCw,
} from "lucide-react";
import type { Analytics, AnalyticsFilter, Breakdown, Link } from "../lib/types";
import { fetchAnalytics, fetchLinks } from "./-api";
import { AppSelect } from "../components/app-select";
import {
  EmptyState,
  ErrorNotice,
  Loading,
  message,
  SectionHeading,
} from "../components/ui";
export const Route = createFileRoute("/_app/analytics")({
  validateSearch: (search: Record<string, unknown>): { linkId?: string } => ({
    ...(typeof search.linkId === "string" ? { linkId: search.linkId } : {}),
  }),
  component: AnalyticsPage,
});
function AnalyticsPage() {
  const search = Route.useSearch();
  const [filter, setFilter] = useState<AnalyticsFilter>({
    days: 30,
    linkId: search.linkId,
  });
  const [links, setLinks] = useState<Link[]>([]);
  const [data, setData] = useState<Analytics | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [refresh, setRefresh] = useState(0);
  useEffect(() => {
    fetchLinks({ data: {} })
      .then(setLinks)
      .catch(() => {});
  }, []);
  useEffect(() => {
    setFilter((current) => ({ ...current, linkId: search.linkId }));
  }, [search.linkId]);
  useEffect(() => {
    let active = true;
    setLoading(true);
    setError("");
    fetchAnalytics({ data: filter })
      .then((value) => {
        if (active) setData(value);
      })
      .catch((err) => {
        if (active) {
          setError(message(err));
          setData(null);
        }
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [filter, refresh]);
  const tags = [...new Set(links.flatMap((link) => link.tags))].sort();
  const campaigns = [
    ...new Set([
      ...(links.map((link) => link.utm.campaign).filter(Boolean) as string[]),
      ...(data?.campaigns.map((item) => item.name).filter(Boolean) || []),
    ]),
  ].sort();
  const change =
    data && data.previousClicks > 0
      ? Math.round(
          ((data.totalClicks - data.previousClicks) / data.previousClicks) *
            100,
        )
      : null;
  return (
    <>
      <SectionHeading
        title="Link analytics"
        action={
          <button
            className="button-secondary"
            disabled={loading}
            onClick={() => setRefresh((n) => n + 1)}
          >
            <RefreshCw size={16} className={loading ? "spin" : ""} />
            Refresh
          </button>
        }
      />
      <div className="analytics-filters">
          <AppSelect
            aria-label="Date range"
            value={String(filter.days)}
            onValueChange={(value) =>
              setFilter({
                ...filter,
                days: Number(value) as 7 | 30 | 90,
              })
            }
            options={[7, 30, 90].map((days) => ({ value: String(days), label: `Last ${days} days` }))}
          />
        <AppSelect
          aria-label="Filter by link"
          value={filter.linkId || ""}
          onValueChange={(value) =>
            setFilter({ ...filter, linkId: value || undefined })
          }
          options={[{ value: "", label: "All links" }, ...links.map((link) => ({ value: link.id, label: link.title || link.slug }))]}
        />
        <AppSelect
          aria-label="Filter by tag"
          value={filter.tag || ""}
          onValueChange={(value) =>
            setFilter({ ...filter, tag: value || undefined })
          }
          options={[{ value: "", label: "All tags" }, ...tags.map((tag) => ({ value: tag, label: tag }))]}
        />
        <AppSelect
          aria-label="Filter by campaign"
          value={filter.campaign || ""}
          onValueChange={(value) =>
            setFilter({ ...filter, campaign: value || undefined })
          }
          options={[{ value: "", label: "All campaigns" }, ...campaigns.map((campaign) => ({ value: campaign, label: campaign }))]}
        />
      </div>
      {loading ? (
        <Loading />
      ) : error ? (
        <ErrorNotice message={error} />
      ) : (
        data && (
          <>
            {data.status !== "ready" && (
              <div
                className={`analytics-notice ${data.status === "unavailable" ? "notice-unavailable" : ""}`}
                role="status"
              >
                <Activity size={18} />
                <div>
                  <strong>
                    {
                      {
                        "no-data": "No clicks recorded",
                        delayed: "Analytics are syncing",
                        unavailable: "Analytics unavailable",
                        ready: "",
                      }[data.status]
                    }
                  </strong>
                  <p>
                    {data.message ||
                      (data.status === "no-data"
                        ? "Share a short link to record clicks."
                        : "Please check back in a moment.")}
                  </p>
                </div>
              </div>
            )}
            {data.status !== "unavailable" && (
              <>
                <div className="stat-grid">
                  <Stat
                    label="Total clicks"
                    value={data.totalClicks.toLocaleString()}
                    icon={<ArrowUpRight size={18} />}
                    detail={
                      change === null
                        ? "Recorded redirects in this period"
                        : `${change >= 0 ? "+" : ""}${change}% vs previous period`
                    }
                  />
                  <Stat
                    label="Links with clicks"
                    value={data.topLinks.length.toLocaleString()}
                    icon={<Link2 size={18} />}
                    detail="Among your top links"
                  />
                  <Stat
                    label="Referrer sources"
                    value={data.referrers.length.toLocaleString()}
                    icon={<Globe2 size={18} />}
                    detail="Among reported sources"
                  />
                </div>
                <section className="chart-card">
                  <div className="card-heading">
                    <div>
                      <h2>Clicks over time</h2>
                      <p>Clicks by day · UTC</p>
                    </div>
                    <span className="chart-legend">
                      <i />
                      Clicks
                    </span>
                  </div>
                  {data.daily.some((day) => day.clicks > 0) ? (
                    <TrafficChart daily={data.daily} />
                  ) : (
                    <EmptyState
                      icon={<BarChart3 size={26} />}
                      title="No clicks in this period"
                    >
                      <p>
                        Once your links are opened, their clicks will appear
                        here.
                      </p>
                    </EmptyState>
                  )}
                </section>
                <div className="breakdown-grid">
                  <section className="breakdown-card">
                    <h2>
                      Top links <ArrowUpRight size={17} />
                    </h2>
                    {data.topLinks.length ? (
                      <div className="top-links">
                        {data.topLinks.map((item) => (
                          <div key={item.linkId}>
                            <span>
                              <strong>{item.title || item.slug}</strong>
                              <small>/r/{item.slug}</small>
                            </span>
                            <b>{item.clicks.toLocaleString()}</b>
                          </div>
                        ))}
                      </div>
                    ) : (
                      <p className="muted">No link traffic in this period.</p>
                    )}
                  </section>
                  <BreakdownCard title="Referrers" items={data.referrers} />
                  <BreakdownCard title="Countries" items={data.countries} />
                  <BreakdownCard title="Devices" items={data.devices} />
                  <BreakdownCard title="Browsers" items={data.browsers} />
                  <BreakdownCard title="Campaigns" items={data.campaigns} />
                </div>
              </>
            )}
          </>
        )
      )}
    </>
  );
}
function Stat({
  label,
  value,
  detail,
  icon,
}: {
  label: string;
  value: string;
  detail: string;
  icon: React.ReactNode;
}) {
  return (
    <div className="stat-card">
      <div>
        {label}
        {icon}
      </div>
      <strong>{value}</strong>
      <p>{detail}</p>
    </div>
  );
}
function BreakdownCard({
  title,
  items,
}: {
  title: string;
  items: Breakdown[];
}) {
  const max = Math.max(...items.map((item) => item.clicks), 1);
  return (
    <section className="breakdown-card">
      <h2>
        {title}
        <ArrowUpRight size={17} />
      </h2>
      {items.length ? (
        <div className="breakdown-bars">
          {items.slice(0, 8).map((item) => (
            <div className="breakdown-row" key={item.name}>
              <div>
                <span>{item.name || "Unknown"}</span>
                <strong>{item.clicks.toLocaleString()}</strong>
              </div>
              <span className="bar-track">
                <i style={{ width: `${(item.clicks / max) * 100}%` }} />
              </span>
            </div>
          ))}
        </div>
      ) : (
        <p className="muted">No {title.toLowerCase()} data in this period.</p>
      )}
    </section>
  );
}
function TrafficChart({ daily }: { daily: Analytics["daily"] }) {
  const max = Math.max(...daily.map((day) => day.clicks), 1);
  const coordinates = daily.map(
    (day, i) =>
      `${50 + (i / Math.max(daily.length - 1, 1)) * 900},${210 - (day.clicks / max) * 165}`,
  );
  return (
    <div className="traffic-chart">
      <svg
        viewBox="0 0 1000 250"
        role="img"
        aria-label={`Daily clicks: ${daily.map((day) => `${day.date}: ${day.clicks}`).join(", ")}`}
      >
        <defs>
          <linearGradient id="chart-fill" x1="0" x2="0" y1="0" y2="1">
            <stop offset="0%" stopColor="#faff69" stopOpacity="0.18" />
            <stop offset="100%" stopColor="#faff69" stopOpacity="0" />
          </linearGradient>
        </defs>
        {[0, 0.5, 1].map((fraction) => (
          <g key={fraction}>
            <line
              x1="50"
              y1={210 - fraction * 165}
              x2="950"
              y2={210 - fraction * 165}
              stroke="#303238"
              strokeDasharray="4 5"
            />
            <text
              x="35"
              y={215 - fraction * 165}
              fill="#92949b"
              fontSize="12"
              textAnchor="end"
            >
              {Math.round(max * fraction)}
            </text>
          </g>
        ))}
        <path
          d={`M50,210 L${coordinates.join(" L")} L950,210 Z`}
          fill="url(#chart-fill)"
        />
        <polyline
          points={coordinates.join(" ")}
          fill="none"
          stroke="#faff69"
          strokeWidth="2.5"
          strokeLinejoin="round"
        />
        {[0, Math.floor((daily.length - 1) / 2), daily.length - 1].map(
          (index, i) => (
            <text
              key={i}
              x={50 + i * 450}
              y="240"
              fontSize="12"
              fill="#92949b"
              textAnchor={i === 0 ? "start" : i === 2 ? "end" : "middle"}
            >
              {daily[index]?.date}
            </text>
          ),
        )}
      </svg>
    </div>
  );
}
