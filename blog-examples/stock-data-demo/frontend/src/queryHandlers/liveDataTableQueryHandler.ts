import { liveTableQuery } from "@/queries";
import { LiveTableResponse } from "@/types/types";
import { queryData } from "./client";

export async function getTableData(
  selectedTickers: Array<string>,
  setStockData: (value: LiveTableResponse) => void,
  setLastRefresh: (value: string) => void
) {

  try {
    const result = await queryData<LiveTableResponse>(
      liveTableQuery, {
        syms: selectedTickers,
      }
    );
    setStockData(result);
    const currTime = new Date();
    setLastRefresh(
      currTime.toLocaleTimeString("it-US") +
        "." +
        currTime.getMilliseconds().toString()
    );
  } catch (err) {
    console.error("Error fetching data from ClickHouse:", err);
    console.error("Failed:", err);
  }
}
