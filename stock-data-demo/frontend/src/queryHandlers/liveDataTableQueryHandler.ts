import { liveTableQuery } from "@/queries";
import { LiveTableResponse } from "@/types/types";
import { ClickHouseError, createClient } from "@clickhouse/client-web";

const client = createClient({
  url: process.env.NEXT_PUBLIC_CLICKHOUSE_URL!,
  username: process.env.NEXT_PUBLIC_CLICKHOUSE_USERNAME!,
  password: process.env.NEXT_PUBLIC_CLICKHOUSE_PASSWORD!,
});

export async function getTableData(
  selectedTickers: Array<string>,
  setStockData: (value: LiveTableResponse) => void,
  setLastRefresh: (value: string) => void
) {

  try {
    const ch_response = await client.query({
      query: liveTableQuery,
      format: "JSONEachRow",
      query_params: {
        syms: selectedTickers,
      },
    });
    const result = (await ch_response.json()) as LiveTableResponse;
    setStockData(result);
    const currTime = new Date();
    setLastRefresh(
      currTime.toLocaleTimeString("it-US") +
        "." +
        currTime.getMilliseconds().toString()
    );
  } catch (err) {
    console.error("Error fetching data from ClickHouse:", err);
    if (err instanceof ClickHouseError) {
      console.error(`ClickHouse error: ${err.code}.  Failed:`, err);
      return;
    }
    console.error("Failed:", err);
  }
  await client.close();
}
