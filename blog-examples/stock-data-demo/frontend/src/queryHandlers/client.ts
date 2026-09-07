export async function queryData<T>(query: string, query_params: Record<string, unknown> = {}): Promise<T> {
  const response = await fetch("/api/query", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ query, query_params }),
    signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) throw new Error(`Query failed (${response.status})`);
  return response.json();
}
