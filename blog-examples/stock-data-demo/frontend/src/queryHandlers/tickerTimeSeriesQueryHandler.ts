import {
  minutePriceHistoricQuery,
  tickerPriceTimerSeriesQuery,
  hourPriceHistoricQuery,
  dayPriceHistoricQuery,
} from "@/queries";
import { PriceTimeSeriesResponse } from "@/types/types";
import { queryData } from "./client";

export async function fetchTickerPriceSeries(
  selectedTicker: string,
  last: string
) {

  try {
    const result = await queryData<PriceTimeSeriesResponse>(
      tickerPriceTimerSeriesQuery, {
        last: last,
        sym: selectedTicker,
      }
    );
    return result;
  } catch (err) {
    console.error("Failed:", err);
  }
}

export async function fetchMinuteTickerPriceSeries(selectedTicker: string) {

  try {
    const result = await queryData<PriceTimeSeriesResponse>(
      minutePriceHistoricQuery, {
        sym: selectedTicker,
      }
    );
    return result;
  } catch (err) {
    console.error("Failed:", err);
  }
}

export async function fetchHourTickerPriceSeries(selectedTicker: string) {

  try {
    const result = await queryData<PriceTimeSeriesResponse>(
      hourPriceHistoricQuery, {
        sym: selectedTicker,
      }
    );
    return result;
  } catch (err) {
    console.error("Failed:", err);
  }
}

export async function fetchDayTickerPriceSeries(selectedTicker: string) {

  try {
    const result = await queryData<PriceTimeSeriesResponse>(
      dayPriceHistoricQuery, {
        sym: selectedTicker,
      }
    );
    return result;
  } catch (err) {
    console.error("Failed:", err);
  }
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

    const result = await queryData<PriceTimeSeriesResponse>(
      query, queryParams
    );
    return result;
  } catch (err) {
    console.error("Failed:", err);
  }
}
