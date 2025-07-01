"use client";

import { ReactElement, useState, useEffect } from "react";
import { Container, Panel, Title, Text } from "@clickhouse/click-ui";
import { LiveDataTable } from "@/components/liveDataTable";
import { LiveStockChart } from "@/components/liveStockChart";
import { getPopularStocks } from "@/queryHandlers/tickerListQueryHandler";

export default function HomeView(): ReactElement {
  const [tableStocks, setTableStocks] = useState<Array<string>>([
    "AAPL",
    "NFLX",
    "MSFT",
    "NVDA",
    "GOOG",
    "META",
    "SPY",
  ]);

  const [selectedStocks, setSelectedStocks] = useState<Array<string>>([]);
  const [popularStocks, setPopularStocks] = useState<Array<string>>([]);

  useEffect(() => {
    getPopularStocks(setPopularStocks);
  }, []);

  function handleRemoveTicker(ticker: string) {
    setTableStocks(tableStocks.filter((item) => item !== ticker));
  }

  function handleAddTicker(ticker: string) {
    setTableStocks([...tableStocks, ticker]);
  }

  function handleSelectTicker(ticker: string) {
    if (selectedStocks.includes(ticker)) {
      return;
    }
    if (selectedStocks.length >= 5) {
      return;
    }
    setSelectedStocks([...selectedStocks, ticker]);
  }

  function handleRemoveSelectedTicker(ticker: string) {
    setSelectedStocks(selectedStocks.filter((item) => item !== ticker));
  }

  const EmptyChartState = (): ReactElement => (
    <Container
      orientation="vertical"
      fillHeight
      fillWidth
      alignItems="start"
      justifyContent="start"
    >
      <Panel
        hasBorder
        orientation="vertical"
        alignItems="center"
        fillWidth
        color="muted"
        padding="xl"
      >
        <Title type="h1">No Ticker Selected</Title>
        <Text color="muted">Select a stock to view the chart</Text>
      </Panel>
    </Container>
  );

  const filteredPopularStocks = popularStocks.filter(
    (ticker) => !tableStocks.includes(ticker)
  );

  return (
    <Container
      orientation="horizontal"
      gap="none"
      fillHeight
      fillWidth
      alignItems="stretch"
      style={{ minHeight: 0, flex: 1 }}
    >
      <Container
        orientation="vertical"
        fillHeight
        padding="md"
        style={{
          width: "800px",
          minWidth: "800px",
          maxWidth: "800px",
          minHeight: 0,
        }}
        gap="md"
      >
        <Title type="h4">My Watchlist</Title>
        <LiveDataTable
          tickers={tableStocks}
          removeTicker={handleRemoveTicker}
          addTicker={handleAddTicker}
          selectTicker={handleSelectTicker}
          selectedTickers={selectedStocks}
          removeSelectedTicker={handleRemoveSelectedTicker}
          hideRefreshInfo={true}
        />

        <Title type="h4">Popular Stocks</Title>
        <LiveDataTable
          tickers={filteredPopularStocks}
          removeTicker={() => {}}
          addTicker={() => {}}
          selectTicker={handleSelectTicker}
          selectedTickers={selectedStocks}
          removeSelectedTicker={handleRemoveSelectedTicker}
          hideAddTicker={true}
          hideRefreshInfo={false}
        />
      </Container>

      <Container
        orientation="vertical"
        fillHeight
        fillWidth
        padding="md"
        style={{
          overflowY: "auto",
          minHeight: 0,
          maxHeight: "100%",
        }}
        gap="md"
      >
        <Title type="h4">Candlesticks</Title>

        {selectedStocks.length === 0 ? (
          <EmptyChartState />
        ) : (
          <Container orientation="vertical" gap="md" fillWidth>
            {selectedStocks.map((ticker) => (
              <LiveStockChart
                key={ticker}
                ticker={ticker}
                removeChart={handleRemoveSelectedTicker}
              />
            ))}
          </Container>
        )}
      </Container>
    </Container>
  );
}
