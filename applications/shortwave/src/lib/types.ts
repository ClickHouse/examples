export type UtmValues = Partial<
  Record<"source" | "medium" | "campaign" | "term" | "content", string>
>;

export type QrStyle = {
  foreground: string;
  background: string;
  dots: "square" | "rounded" | "dots";
  /** "clickhouse" and legacy null values use the bundled SVG. Uploads are raster data URLs only. */
  logo: string | null;
};

export type Folder = { id: string; name: string };

export type Link = {
  id: string;
  slug: string;
  domainId: string | null;
  domainHostname: string | null;
  title: string;
  destination: string;
  resolvedUrl: string;
  utm: UtmValues;
  tags: string[];
  folderId: string | null;
  enabled: boolean;
  createdAt: string;
  updatedAt: string;
  qrStyle: QrStyle;
};

export type LinkInput = {
  destination: string;
  title?: string;
  slug?: string;
  domainId?: string | null;
  utm?: UtmValues;
  tags?: string[];
  folderId?: string | null;
  enabled?: boolean;
};

export type UtmTemplate = {
  id: string;
  name: string;
  values: UtmValues;
  createdAt: string;
};

export type AnalyticsFilter = {
  days?: 7 | 30 | 90;
  linkId?: string;
  campaign?: string;
  tag?: string;
};
export type Breakdown = { name: string; clicks: number };
export type Analytics = {
  status: "ready" | "no-data" | "delayed" | "unavailable";
  message: string | null;
  totalClicks: number;
  previousClicks: number;
  daily: { date: string; clicks: number }[];
  topLinks: { linkId: string; title: string; slug: string; clicks: number }[];
  referrers: Breakdown[];
  countries: Breakdown[];
  devices: Breakdown[];
  browsers: Breakdown[];
  campaigns: Breakdown[];
  lastEventAt: string | null;
  pendingEvents: number;
};

export type ClickEvent = {
  event_id: string;
  account_id: string;
  link_id: string;
  occurred_at: string;
  utm_source: string;
  utm_medium: string;
  utm_campaign: string;
  utm_term: string;
  utm_content: string;
  referrer_domain: string;
  country: string;
  device: string;
  browser: string;
  is_bot: number;
  is_demo: number;
};
