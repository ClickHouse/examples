import { tickerListQuery, popularStocksQuery } from "@/queries";
import { TickerListResponse } from "@/types/types";
import { ClickHouseError, createClient } from "@clickhouse/client-web";

const client = createClient({
  url: process.env.NEXT_PUBLIC_CLICKHOUSE_URL!,
  username: process.env.NEXT_PUBLIC_CLICKHOUSE_USERNAME!,
  password: process.env.NEXT_PUBLIC_CLICKHOUSE_PASSWORD!,
});

export async function getTickerList(
  setTickerList: React.Dispatch<React.SetStateAction<TickerListResponse>>
) {

  try {
    const query_response = await client.query({
      query: tickerListQuery,
      format: "JSONEachRow",
    });
    const result = (await query_response.json()) as TickerListResponse;
    setTickerList(result);
  } catch (err) {
    if (err instanceof ClickHouseError) {
      console.error(`ClickHouse error: ${err.code}.  Failed:`, err);
      return;
    }
    console.error("Failed:", err);
  }
  await client.close();
}

export async function getPopularStocks(
  setPopularStocks: React.Dispatch<React.SetStateAction<string[]>>
) {

  try {
    const query_response = await client.query({
      query: popularStocksQuery,
      format: "JSONEachRow",
    });
    const result = (await query_response.json()) as { sym: string }[];
    setPopularStocks(result.map((item) => item.sym));
  } catch (err) {
    if (err instanceof ClickHouseError) {
      console.error(`ClickHouse error: ${err.code}.  Failed:`, err);
      return;
    }
    console.error("Failed:", err);
  }
  await client.close();
}
