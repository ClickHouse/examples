require("dotenv").config();
const { createClient } = require("@clickhouse/client");

function createClickHouseClient(overrides = {}) {
  return createClient({
    url: process.env.CLICKHOUSE_URL || "http://localhost:8123",
    username: process.env.CLICKHOUSE_USERNAME || "default",
    password: process.env.CLICKHOUSE_PASSWORD || "",
    database: process.env.CLICKHOUSE_DATABASE || "default",
    request_timeout: 15000,
    max_open_connections: 10,
    compression: { request: true, response: true },
    clickhouse_settings: { async_insert: 0 },
    ...overrides,
  });
}
module.exports = { createClickHouseClient };
