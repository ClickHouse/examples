"use client";
import { ReactElement, useEffect, useState } from "react";
import {
  Container,
  Icon,
  Panel,
  Spacer,
  Text,
  Title,
  useCUITheme,
  Button,
  IconButton,
  ButtonGroup,
} from "@clickhouse/click-ui";
import { Chart } from "react-chartjs-2";
import _ from "lodash";
import {
  Chart as ChartJS,
  LineController,
  LineElement,
  PointElement,
  LinearScale,
  ChartOptions,
  Tooltip,
  Legend,
  ChartData,
} from "chart.js";
import {
  CandlestickController,
  CandlestickElement,
  OhlcController,
  OhlcElement,
} from "chartjs-chart-financial";
import {
  RealTimeScale,
  StreamingPlugin,
} from "@robloche/chartjs-plugin-streaming";

import "chartjs-adapter-moment";
import {
  fetchMinuteTickerPriceSeries,
  fetchHourTickerPriceSeries,
  fetchDayTickerPriceSeries,
  fetchTickerPriceSeries,
} from "@/queryHandlers/tickerTimeSeriesQueryHandler";
import {
  tickerPriceTimerSeriesQuery,
  minutePriceHistoricQuery,
  hourPriceHistoricQuery,
  dayPriceHistoricQuery,
} from "@/queries";
import numeral from "numeral";
import {
  ChartLineSeries,
  ChartVolumeSeries,
  LiveStockChartProps,
  PriceTimeSeriesData,
  TimeWindow,
} from "@/types/types";

const TIME_WINDOWS: TimeWindow[] = [
  {
    id: "5min",
    label: "5M",
    refreshInterval: 500,
    query: tickerPriceTimerSeriesQuery,
  },
  {
    id: "30min",
    label: "30M",
    refreshInterval: 1000,
    query: minutePriceHistoricQuery,
  },
  {
    id: "1hour",
    label: "1H",
    refreshInterval: 15000,
    query: hourPriceHistoricQuery,
  },
  {
    id: "1day",
    label: "1D",
    refreshInterval: 60000,
    query: dayPriceHistoricQuery,
  },
];

export const LiveStockChart = ({
  ticker,
  removeChart,
}: LiveStockChartProps): ReactElement => {
  const [selectedTimeWindow, setSelectedTimeWindow] = useState<TimeWindow>(
    TIME_WINDOWS[1]
  );

  if (!ticker) {
    return (
      <Panel
        hasBorder
        orientation="vertical"
        fillHeight
        fillWidth
        alignItems="center"
        color="muted"
      >
        <Title type="h1">No Ticker Selected</Title>
        <Text color="muted">Select a stock to view the chart</Text>
      </Panel>
    );
  }

  function onRefresh(
    ticker: string,
    chart: ChartJS,
    setCandleData: React.Dispatch<React.SetStateAction<PriceTimeSeriesData>>,
    setLineData: React.Dispatch<React.SetStateAction<ChartLineSeries>>,
    setVolumeData: React.Dispatch<React.SetStateAction<ChartVolumeSeries>>,
    timeWindow: TimeWindow
  ) {
    const fetchFunction = getFetchFunction(timeWindow.id);

    fetchFunction(ticker).then((values) => {
      if (values) {
        const converted = values.map((value) =>
          Object.assign(value, { x: parseInt(value.x) })
        );
        const convertedLine: ChartLineSeries = values.map((value) => {
          return {
            x: parseInt(value.x),
            y: value.c,
          };
        });
        const convertedBar: ChartVolumeSeries = values.map((value) => {
          return {
            x: parseInt(value.x),
            y: value.v,
          };
        });
        setCandleData(converted);
        setLineData(convertedLine);
        setVolumeData(convertedBar);
      }
    });
  }

  function getFetchFunction(timeWindowId: string) {
    switch (timeWindowId) {
      case "5min":
        return (ticker: string) => fetchTickerPriceSeries(ticker, "0");
      case "30min":
        return fetchMinuteTickerPriceSeries;
      case "1hour":
        return fetchHourTickerPriceSeries;
      case "1day":
        return fetchDayTickerPriceSeries;
      default:
        return fetchMinuteTickerPriceSeries;
    }
  }

  return (
    <Panel
      hasBorder
      orientation="vertical"
      fillWidth
      alignItems="center"
      color="muted"
      style={{ height: "500px", minHeight: "500px" }}
    >
      <Container
        orientation="horizontal"
        justifyContent="space-between"
        alignItems="center"
        fillWidth
        padding="md"
      >
        <Container padding="none" orientation="horizontal" fillWidth>
          <Title type="h1">{ticker}</Title>
        </Container>
        <Container
          orientation="horizontal"
          gap="xs"
          alignItems="center"
          justifyContent="end"
        >
          <ButtonGroup
            options={TIME_WINDOWS.map((timeWindow) => ({
              label: timeWindow.label,
              value: timeWindow.id,
            }))}
            selected={selectedTimeWindow.id}
            onClick={(value: string) => {
              const selectedWindow = TIME_WINDOWS.find(
                (timeWindow) => timeWindow.id === value
              );
              if (selectedWindow) {
                setSelectedTimeWindow(selectedWindow);
              }
            }}
          />

          {removeChart && (
            <IconButton
              type="primary"
              icon="cross"
              onClick={() => removeChart(ticker)}
            />
          )}
        </Container>
      </Container>
      <div style={{ height: "400px", width: "100%" }}>
        <ChartObject
          ticker={ticker}
          onRefresh={onRefresh}
          timeWindow={selectedTimeWindow}
        />
      </div>
    </Panel>
  );
};

const ChartObject = ({
  ticker,
  onRefresh,
  timeWindow,
}: {
  ticker: string;
  onRefresh: (
    ticker: string,
    chart: any,
    setCandleData: React.Dispatch<React.SetStateAction<PriceTimeSeriesData>>,
    setLineData: React.Dispatch<React.SetStateAction<ChartLineSeries>>,
    setVolumeData: React.Dispatch<React.SetStateAction<ChartVolumeSeries>>,
    timeWindow: TimeWindow
  ) => void;
  timeWindow: TimeWindow;
}): ReactElement => {
  ChartJS.register(
    OhlcController,
    OhlcElement,
    CandlestickController,
    CandlestickElement,
    LinearScale,
    PointElement,
    LineElement,
    LineController,
    Legend,
    Tooltip,
    StreamingPlugin,
    RealTimeScale
  );
  const CUITheme = useCUITheme();
  const [candleData, setCandleData] = useState<PriceTimeSeriesData>([]);
  const [lineData, setLineData] = useState<ChartLineSeries>([]);
  const [volumeData, setVolumeData] = useState<ChartVolumeSeries>([]);

  useEffect(() => {
    setCandleData([]);
    setLineData([]);
    setVolumeData([]);

    const fetchFunction = getFetchFunction(timeWindow.id);
    fetchFunction(ticker).then((values) => {
      if (values) {
        const converted: PriceTimeSeriesData = values.map((value) =>
          Object.assign(value, { x: parseInt(value.x) })
        );
        const convertedLine: ChartLineSeries = values.map((value) => {
          return {
            x: parseInt(value.x),
            y: value.c,
          };
        });
        const convertedBar: ChartVolumeSeries = values.map((value) => {
          return {
            x: parseInt(value.x),
            y: value.v,
          };
        });
        setCandleData(converted);
        setLineData(convertedLine);
        setVolumeData(convertedBar);
      }
    });
  }, [ticker, timeWindow]);

  function getFetchFunction(timeWindowId: string) {
    switch (timeWindowId) {
      case "5min":
        return (ticker: string) => fetchTickerPriceSeries(ticker, "0");
      case "30min":
        return fetchMinuteTickerPriceSeries;
      case "1hour":
        return fetchHourTickerPriceSeries;
      case "1day":
        return fetchDayTickerPriceSeries;
      default:
        return fetchMinuteTickerPriceSeries;
    }
  }

  if (candleData.length === 0) {
    return (
      <Container
        fillWidth
        fillHeight
        orientation="vertical"
        alignItems="center"
        justifyContent="center"
      >
        <Icon name="horizontal-loading" size="xxl" />
      </Container>
    );
  }

  const data: ChartData = {
    labels: ["Candle", "Line"],
    datasets: [
      {
        type: "candlestick",
        data: candleData,
        label: "Candle",
        borderColor: CUITheme.global.color.feedback.info.foreground,
        backgroundColor: CUITheme.global.color.feedback.info.background,
        backgroundColors: {
          up: CUITheme.global.color.feedback.success.background,
          down: CUITheme.global.color.feedback.danger.background,
          unchanged: CUITheme.global.color.feedback.neutral.background,
        },
        borderColors: {
          up: CUITheme.global.color.feedback.success.foreground,
          down: CUITheme.global.color.feedback.danger.foreground,
          unchanged: CUITheme.global.color.feedback.neutral.foreground,
        },
        yAxisID: "y",
      },
      {
        type: "line",
        data: lineData,
        label: "Close",
        borderColor: CUITheme.global.color.feedback.neutral.background,
        backgroundColor: CUITheme.global.color.feedback.neutral.background,
        yAxisID: "y",
      },
      {
        type: "bar",
        data: volumeData,
        label: "Volume",
        borderColor: CUITheme.global.color.feedback.neutral.background,
        backgroundColor: CUITheme.global.color.feedback.neutral.background,
        yAxisID: "y1",
      },
    ],
  };

  const getChartDuration = (timeWindowId: string) => {
    switch (timeWindowId) {
      case "5min":
        return 5 * 60 * 1000;
      case "30min":
        return 30 * 60 * 1000;
      case "1hour":
        return 60 * 60 * 1000;
      case "1day":
        return 24 * 60 * 60 * 1000;
      default:
        return 30 * 60 * 1000;
    }
  };

  const options: ChartOptions = {
    scales: {
      x: {
        type: "realtime",
        ticks: {
          source: "auto",
          color: CUITheme.global.color.text.muted,
        },
        title: {
          display: true,
          text: "Time",
        },
        grid: {
          color: CUITheme.global.color.stroke.muted,
        },
        border: {
          color: CUITheme.global.color.stroke.default,
        },
        realtime: {
          duration: getChartDuration(timeWindow.id),
          refresh: timeWindow.refreshInterval,
          delay: 0,
          ttl: undefined,
          onRefresh: (chart) => {
            onRefresh(
              ticker,
              chart,
              setCandleData,
              setLineData,
              setVolumeData,
              timeWindow
            );
          },
        },
      },
      y: {
        position: "left",
        title: {
          display: true,
          text: "Price",
        },
        border: {
          color: CUITheme.global.color.stroke.default,
        },
        grid: {
          color: CUITheme.global.color.stroke.muted,
        },
        min:
          candleData.length > 0
            ? Math.min(...candleData.map((val) => val.l)) - 0.25
            : 0,
        max:
          candleData.length > 0
            ? Math.max(...candleData.map((val) => val.h)) + 0.25
            : 1,
        ticks: {
          includeBounds: false,
          callback: (value, index, ticks) => {
            let val;
            if (typeof value === "string") {
              val = parseFloat(value).toFixed(2);
            } else {
              val = value.toFixed(2);
            }
            return "$" + val;
          },
          color: CUITheme.global.color.text.muted,
        },
      },
      y1: {
        position: "right",
        type: "linear",
        title: {
          display: true,
          text: "Volume",
        },
        grid: {
          drawOnChartArea: false,
        },
        min: 0,
        max:
          volumeData.length > 0
            ? Math.max(...volumeData.map((val) => val.y)) * 5
            : 1,
        ticks: {
          includeBounds: false,
          callback: (value, index, ticks) => {
            return numeral(value).format("0.0a");
          },
        },
      },
    },
    interaction: {
      intersect: false,
    },
    animation: {
      duration: 0,
    },
    plugins: {
      legend: {
        display: false,
      },

      tooltip: {
        position: "nearest",
      },
    },
    elements: {
      line: {
        capBezierPoints: true,
      },
    },
    maintainAspectRatio: false,
  };
  return <Chart type="candlestick" data={data} options={options} />;
};
