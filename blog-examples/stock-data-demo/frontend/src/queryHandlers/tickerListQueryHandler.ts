import { tickerListQuery, popularStocksQuery } from "@/queries";
import { TickerListResponse } from "@/types/types";
import { queryData } from "./client";

export async function getTickerList(
  setTickerList: React.Dispatch<React.SetStateAction<TickerListResponse>>
) {

  try {
    const result = await queryData<TickerListResponse>(
      tickerListQuery, {}
    );
    setTickerList(result);
  } catch (err) {
    console.error("Failed:", err);
  }
}

export async function getPopularStocks(
  setPopularStocks: React.Dispatch<React.SetStateAction<string[]>>
) {

  try {
    const result = await queryData<{ sym: string }[]>(
      popularStocksQuery, {}
    );
    setPopularStocks(result.map((item) => item.sym));
  } catch (err) {
    console.error("Failed:", err);
  }
}
