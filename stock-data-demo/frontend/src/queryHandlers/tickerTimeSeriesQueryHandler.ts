import {
  minutePriceHistoricQuery,
  tickerPriceTimerSeriesQuery,
  hourPriceHistoricQuery,
  dayPriceHistoricQuery,
} from "@/queries";
import { PriceTimeSeriesResponse } from "@/types/types";
import { ClickHouseError, createClient } from "@clickhouse/client-web";

const client = createClient({
  url: process.env.NEXT_PUBLIC_CLICKHOUSE_URL!,
  username: process.env.NEXT_PUBLIC_CLICKHOUSE_USERNAME!,
  password: process.env.NEXT_PUBLIC_CLICKHOUSE_PASSWORD!,
});

export async function fetchTickerPriceSeries(
  selectedTicker: string,
  last: string
) {

  try {
    const ch_response = await client.query({
      query: tickerPriceTimerSeriesQuery,
      format: "JSONEachRow",
      query_params: {
        last: last,
        sym: selectedTicker,
      },
    });
    const result = (await ch_response.json()) as PriceTimeSeriesResponse;
    return result;
  } catch (err) {
    if (err instanceof ClickHouseError) {
      console.error(`ClickHouse error: ${err.code}.  Failed:`, err);
      return;
    }
    console.error("Failed:", err);
  }
  await client.close();
}

export async function fetchMinuteTickerPriceSeries(selectedTicker: string) {

  try {
    const ch_response = await client.query({
      query: minutePriceHistoricQuery,
      format: "JSONEachRow",
      query_params: {
        sym: selectedTicker,
      },
    });
    const result = (await ch_response.json()) as PriceTimeSeriesResponse;
    return result;
  } catch (err) {
    if (err instanceof ClickHouseError) {
      console.error(`ClickHouse error: ${err.code}.  Failed:`, err);
      return;
    }
    console.error("Failed:", err);
  }
  await client.close();
}

export async function fetchHourTickerPriceSeries(selectedTicker: string) {

  try {
    const ch_response = await client.query({
      query: hourPriceHistoricQuery,
      format: "JSONEachRow",
      query_params: {
        sym: selectedTicker,
      },
    });
    const result = (await ch_response.json()) as PriceTimeSeriesResponse;
    return result;
  } catch (err) {
    if (err instanceof ClickHouseError) {
      console.error(`ClickHouse error: ${err.code}.  Failed:`, err);
      return;
    }
    console.error("Failed:", err);
  }
  await client.close();
}

export async function fetchDayTickerPriceSeries(selectedTicker: string) {

  try {
    const ch_response = await client.query({
      query: dayPriceHistoricQuery,
      format: "JSONEachRow",
      query_params: {
        sym: selectedTicker,
      },
    });
    const result = (await ch_response.json()) as PriceTimeSeriesResponse;
    return result;
  } catch (err) {
    if (err instanceof ClickHouseError) {
      console.error(`ClickHouse error: ${err.code}.  Failed:`, err);
      return;
    }
    console.error("Failed:", err);
  }
  await client.close();
}

export async function fetchTickerPriceSeriesByQuery(
  selectedTicker: string,
  query: string,
  last?: string
) {

  try {
    const queryParams: any = { sym: selectedTicker };
    if (last) {
      queryParams.last = last;
    }

    const ch_response = await client.query({
      query: query,
      format: "JSONEachRow",
      query_params: queryParams,
    });
    const result = (await ch_response.json()) as PriceTimeSeriesResponse;
    return result;
  } catch (err) {
    if (err instanceof ClickHouseError) {
      console.error(`ClickHouse error: ${err.code}.  Failed:`, err);
      return;
    }
    console.error("Failed:", err);
  }
  await client.close();
}
