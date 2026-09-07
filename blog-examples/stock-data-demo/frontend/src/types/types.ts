export interface TimeWindow {
  id: string;
  label: string;
  refreshInterval: number;
  query: string;
}

export interface LiveStockChartProps {
  ticker: string | undefined;
  removeChart?: (ticker: string) => void;
}

export interface LiveStockComponent extends LiveStockChartProps {
  onRefresh: (
    ticker: string,
    chart: any,
    setCandleData: React.Dispatch<React.SetStateAction<PriceTimeSeriesData>>,
    setLineData: React.Dispatch<React.SetStateAction<ChartLineSeries>>,
    setVolumeData: React.Dispatch<React.SetStateAction<ChartVolumeSeries>>,
    timeWindow: TimeWindow
  ) => void;
}

export interface LiveDataTableProps {
  tickers: Array<string>;
  removeTicker: (ticker: string) => void;
  addTicker: (ticker: string) => void;
  selectTicker: (ticker: string) => void;
  selectedTickers: Array<string>;
  removeSelectedTicker: (ticker: string) => void;
  hideAddTicker?: boolean;
  hideRefreshInfo?: boolean;
}

export type LiveTableDataRecord = {
  ticker: string;
  last: number;
  bid: number;
  ask: number;
  change: number;
  volume: number;
  latency: number;
};

export type LiveTableResponse = Array<LiveTableDataRecord>;

export type ChartLineSeriesRecord = {
  x: number;
  y: number;
};
export type ChartLineSeries = Array<ChartLineSeriesRecord>;

export type ChartVolumeSeriesRecord = {
  x: number;
  y: number;
};

export type ChartVolumeSeries = Array<ChartVolumeSeriesRecord>;

export type PriceTimeSeriesResponseRecord = {
  x: string;
  o: number;
  h: number;
  l: number;
  c: number;
  v: number;
};
export type PriceTimeSeriesDataRecord = {
  x: number;
  o: number;
  h: number;
  l: number;
  c: number;
  v: number;
};
export type PriceTimeSeriesResponse = Array<PriceTimeSeriesResponseRecord>;
export type PriceTimeSeriesData = Array<PriceTimeSeriesDataRecord>;

export type ChartSeriesData = {
  data: PriceTimeSeriesData | ChartLineSeries;
  label: string;
  type?: string;
  id?: number;
  backgroundColor?: string;
  borderColor?: string;
  cubicInterpolationMode?: string;
  backgroundColors?: {
    up: string;
    down: string;
    unchanged: string;
  };
  borderColors?: {
    up: string;
    down: string;
    unchanged: string;
  };
  yAxisID?: string;
};
export type ChartSeriesDatasetItem = {
  labels?: Array<string>;
  datasets: Array<ChartSeriesData>;
};

export type TickerListRecord = {
  sym: string;
  last_price: number;
  change_pct: number;
};
export type TickerListResponse = Array<TickerListRecord>;

export type TickerListHelper = {
  filteredTickers: TickerListResponse;
  addTicker: (ticker: string) => void;
};
