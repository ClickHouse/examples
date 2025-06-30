"use client";
import { getTableData } from "@/queryHandlers/liveDataTableQueryHandler";
import { getTickerList } from "@/queryHandlers/tickerListQueryHandler";
import {
  LiveDataTableProps,
  LiveTableResponse,
  TickerListHelper,
  TickerListResponse,
} from "@/types/types";
import {
  Badge,
  Button,
  Container,
  Dropdown,
  IconButton,
  Panel,
  SearchField,
  Table,
  TableHeaderType,
  TableRowType,
  Text,
  useCUITheme,
} from "@clickhouse/click-ui";

import numeral from "numeral";
import { ReactElement, useEffect, useState } from "react";
import { FixedSizeList, ListChildComponentProps } from "react-window";
import { styled } from "styled-components";

const StyledSearchField = styled(SearchField)`
  & > input {
    border: "none";
  }
`;

const TableFooter = styled(Panel)`
  border-top: none;
  border-top-right-radius: 0;
  border-top-left-radius: 0;
  border-bottom-right-radius: 0.25rem;
  border-bottom-left-radius: 0.25rem;
`;

const TableWithoutFooter = styled(Table)`
  border-bottom-right-radius: 0;
  border-bottom-left-radius: 0;
  border-bottom: none;
`;

export const LiveDataTable = ({
  tickers,
  removeTicker,
  addTicker,
  selectTicker,
  selectedTickers,
  removeSelectedTicker,
  hideAddTicker = false,
  hideRefreshInfo = false,
}: LiveDataTableProps): ReactElement => {
  const [stockData, setStockData] = useState<LiveTableResponse>([]);
  const [newTickerVal, setNewTickerVal] = useState<string>();
  const [tickerList, setTickerList] = useState<TickerListResponse>([]);
  const [lastRefresh, setLastRefresh] = useState<string>();
  const handleAddTicker = (ticker: string): void => {
    addTicker(ticker), setNewTickerVal(undefined);
  };
  const CUITheme = useCUITheme();
  useEffect(() => {
    getTickerList(setTickerList);
    getTableData(tickers, setStockData, () => {
      setLastRefresh;
    });
  }, []);

  useEffect(() => {
    getTableData(tickers, setStockData, () => {
      setLastRefresh;
    });
    const liveTableInterval = setInterval(() => {
      getTableData(tickers, setStockData, setLastRefresh);
    }, 100);
    return () => clearInterval(liveTableInterval);
  }, [tickers]);
  const filteredTickerSelectors = tickerList.filter(
    (ticker) => !tickers.includes(ticker.sym)
  );

  const tableHeaders: Array<TableHeaderType> = [
    { label: "Ticker", width: "125px" },
    { label: "Last", width: "125px" },
    { label: "Bid", width: "125px" },
    { label: "Ask", width: "125px" },
    { label: "Volume", width: "100px" },
    { label: "Change %", width: "110px" },
    { label: "", width: "75px" },
  ];
  const addTickerRow: TableRowType = {
    id: "addTicker",
    items: [
      {
        label: (
          <TickerSelector
            tickers={filteredTickerSelectors}
            addTicker={addTicker}
          />
        ),
      },
      {
        label: "",
      },
      { label: "" },
      { label: "" },
      { label: "" },
      { label: "" },
      { label: "" },
    ],
  };
  const tableRows: Array<TableRowType> = tickers.map((ticker) => {
    const stock = stockData.find((item) => item.ticker === ticker);
    const isSelected = selectedTickers.includes(ticker);
    const canSelectMore = selectedTickers.length < 5;

    return {
      id: ticker,
      onClick: () => {
        if (!isSelected && canSelectMore) {
          selectTicker(ticker);
        }
      },
      style: isSelected
        ? { backgroundColor: CUITheme.global.color.background.muted }
        : undefined,
      items: [
        {
          label: (
            <Container
              orientation="horizontal"
              alignItems="center"
              gap="xs"
              padding="none"
            >
              <Text>{ticker}</Text>
            </Container>
          ),
        },
        {
          label: (
            <FlashingCell
              curVal={stock?.last ?? undefined}
              change={stock?.change ?? undefined}
              dollars
            />
          ),
        },
        {
          label: (
            <FlashingCell
              curVal={stock?.bid ?? undefined}
              change={stock?.change ?? undefined}
              dollars
            />
          ),
        },
        {
          label: (
            <FlashingCell
              curVal={stock?.ask ?? undefined}
              change={stock?.change ?? undefined}
              dollars
            />
          ),
        },
        {
          label: (
            <FlashingCell
              curVal={stock?.volume ?? undefined}
              change={stock?.change ?? undefined}
              volNum
            />
          ),
        },
        {
          label: (
            <FlashingCell
              curVal={stock?.change ?? undefined}
              change={stock?.change ?? undefined}
            />
          ),
        },
        {
          label: hideAddTicker ? (
            ""
          ) : (
            <Container
              orientation="horizontal"
              gap="xs"
              alignItems="center"
              padding="none"
            >
              <IconButton
                type="ghost"
                size="xs"
                icon="cross"
                onClick={() => {
                  removeTicker(ticker);
                }}
              />
              {isSelected && (
                <IconButton
                  type="ghost"
                  size="xs"
                  icon="eye"
                  onClick={() => {
                    removeSelectedTicker(ticker);
                  }}
                />
              )}
            </Container>
          ),
        },
      ],
    };
  });
  return (
    <Container
      fillWidth
      fillHeight
      alignItems="start"
      orientation="vertical"
      gap="md"
    >
      <Container orientation="vertical" fillWidth gap="none" padding="none">
        {hideAddTicker ? (
          <Table headers={tableHeaders} rows={tableRows} />
        ) : (
          <>
            <TableWithoutFooter headers={tableHeaders} rows={tableRows} />
            <TableFooter hasBorder fillWidth padding="sm">
              <TickerSelector
                tickers={filteredTickerSelectors}
                addTicker={addTicker}
              />
            </TableFooter>
          </>
        )}
      </Container>
      {!hideRefreshInfo && (
        <Container
          orientation="horizontal"
          justifyContent="space-between"
          fillWidth
        >
          <Text color="muted">Last refresh at: {lastRefresh}</Text>
        </Container>
      )}
    </Container>
  );
};

const FlashingCell = ({
  curVal,
  change,
  volNum = false,
  dollars = false,
}: {
  curVal?: number;
  change?: number;
  volNum?: boolean;
  dollars?: boolean;
}): ReactElement => {
  if (!curVal) {
    return (
      <div>
        <Text> - </Text>
      </div>
    );
  }
  const formattedVal = volNum
    ? numeral(curVal).format("0.0a")
    : dollars
    ? `$${curVal.toFixed(2)}`
    : curVal.toFixed(2);
  if (change === 0 || !change) {
    return (
      <div>
        <Text>{formattedVal}</Text>
      </div>
    );
  } else if (change < 0) {
    return (
      <div key={formattedVal} className="blinkRed">
        <p>{formattedVal}</p>
      </div>
    );
  } else {
    return (
      <div key={formattedVal} className="blinkGreen">
        <p>{formattedVal}</p>
      </div>
    );
  }
};

const TickerSelector = ({
  tickers,
  addTicker,
}: {
  tickers: TickerListResponse;
  addTicker: (ticker: string) => void;
}): ReactElement => {
  const [filterVal, setFilterVal] = useState<string>("");
  const filteredTickers =
    filterVal !== ""
      ? tickers.filter((ticker) => ticker.sym.includes(filterVal.toUpperCase()))
      : tickers;
  const tickerRow: React.FC<ListChildComponentProps<TickerListHelper>> = ({
    index,
    style,
    data,
  }) => {
    const { filteredTickers, addTicker } = data;
    const item = filteredTickers[index];
    return (
      <Dropdown.Item
        key={item.sym}
        style={style}
        onClick={() => addTicker(item.sym)}
      >
        <Container
          orientation="horizontal"
          gap="md"
          padding="none"
          justifyContent="space-between"
          fillWidth
        >
          <Text>{item.sym}</Text>
          <Badge
            text={`$${item.last_price.toFixed(2)} (${item.change_pct.toFixed(
              2
            )}%)`}
            state={item.change_pct >= 0 ? "success" : "danger"}
            size="sm"
            icon={item.change_pct >= 0 ? "arrow-up" : "arrow-down"}
            iconDir="end"
          />
        </Container>
      </Dropdown.Item>
    );
  };
  return (
    <Dropdown>
      <Dropdown.Trigger>
        <Button type="secondary" label="Add a ticker" iconLeft="plus" />
      </Dropdown.Trigger>
      <Dropdown.Content side="right" align="end" sideOffset={6}>
        <StyledSearchField
          placeholder="Search for a ticker"
          value={filterVal}
          onChange={setFilterVal}
        />
        <FixedSizeList
          height={
            filteredTickers.length > 7 ? 250 : 35 * filteredTickers.length
          }
          itemCount={filteredTickers.length}
          width={400}
          itemSize={35}
          itemData={{ filteredTickers, addTicker }}
        >
          {tickerRow}
        </FixedSizeList>
      </Dropdown.Content>
    </Dropdown>
  );
};
