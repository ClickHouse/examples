# Real-time stock data with ClickHouse and Massive

Companion example for [Build a real-time market data app with ClickHouse and Massive](https://clickhouse.com/blog/build-a-real-time-market-data-app-with-clickhouse-and-polygonio). [Massive](https://massive.com/) was formerly Polygon.io.

A Node.js service subscribes to stock trades and quotes, batches them into ClickHouse, and serves a React dashboard with a watchlist, candlestick charts, and ingestion controls. Browser requests use named, parameterized server queries; database credentials stay on the server.

## Requirements

- Node.js 22 or later and npm.
- A local ClickHouse server or ClickHouse Cloud service, and an existing database. Setup needs `CREATE TABLE`; the app needs `SELECT` and `INSERT` on `trades` and `quotes`.
- For live data, a Massive API key with **both stock trades (`T`) and quotes (`Q`) WebSocket access**. API access alone is insufficient: check the [trades](https://massive.com/docs/websocket/stocks/trades) and [quotes](https://massive.com/docs/websocket/stocks/quotes) entitlements for your plan. There is no need for a key to try synthetic sample data.

## Run

```sh
git clone https://github.com/ClickHouse/examples.git
cd examples/blog-examples/stock-data-demo
npm ci
cp env.example .env
```

Edit `.env` with your ClickHouse connection and, for live data, `MASSIVE_API_KEY`. The file is ignored by Git. Use `CLICKHOUSE_URL=https://<your-service>:8443` for ClickHouse Cloud, with the credentials from the service's Connect panel. Never use `NEXT_PUBLIC_` variables for credentials.

For local ClickHouse, install [clickhousectl](https://github.com/ClickHouse/clickhousectl) and run these commands from the example directory:

```sh
clickhousectl local server start stock-demo
clickhousectl local server list
```

Set `CLICKHOUSE_URL=http://localhost:<http_port>` to the port reported by the CLI. Then:

```sh
npm run setup  # Creates the tables in scripts/ddl.sql
npm run build  # Exports the frontend into frontend/out
npm start
```

Open:

- [Dashboard](http://localhost:34567/stocks/): watchlist and charts. Click a ticker to open a chart.
- [Admin](http://localhost:34567/admin): connection status, insert metrics, and start/pause/stop/restart controls.
- [Landing page](http://localhost:34567/) and JSON [health](http://localhost:34567/health) / [metrics](http://localhost:34567/metrics).

The demo binds to `127.0.0.1` by default. Its query and control endpoints have no authentication; add access controls before exposing it to other users.

### Try it without market access

Use a separate database from any real market data, leave `MASSIVE_API_KEY` empty, and run:

```sh
npm run seed
npm run build
npm start
```

The seed adds 540 synthetic trades and 540 synthetic quotes for AAPL, MSFT, and NVDA, timestamped over the last three minutes. Prices are fabricated. It appends on each run; rerun it to refresh the data after the chart window expires. No external market API is called.

### Development

```sh
npm run dev
```

Open `http://localhost:3000/stocks/` or `http://localhost:3000/stocks/admin/`. The Next.js development server forwards API and control requests to the backend on port 34567 (or `BACKEND_PORT`, if exported in your shell to match a custom backend `PORT`). The production server at 34567 serves the last build; rebuild after frontend changes.

## Configuration

See [env.example](./env.example) for all settings.

| Variable | Default | Purpose |
| --- | --- | --- |
| `CLICKHOUSE_URL` | `http://localhost:8123` | Server HTTP(S) endpoint |
| `CLICKHOUSE_USERNAME` / `CLICKHOUSE_PASSWORD` | `default` / empty | Server-side credentials |
| `CLICKHOUSE_DATABASE` | `default` | Existing database |
| `MASSIVE_API_KEY` | empty | Live market-data key |
| `MASSIVE_WS_URL` | `wss://socket.massive.com/stocks` | Stock feed endpoint |
| `MASSIVE_SYMBOLS` | `AAPL,MSFT,NVDA` | Comma-separated symbols; `*` subscribes to the entire market |
| `AUTO_START` | `true` | Set `false` to start via the admin UI |
| `HOST` / `PORT` | `127.0.0.1` / `34567` | Backend listener |
| `KAFKA_ENABLED` | `false` | Optional copy to Kafka after successful ClickHouse inserts |

If using a delayed feed, set `MASSIVE_WS_URL=wss://delayed.massive.com/stocks` and verify your plan grants access to both channels there. A delayed feed can leave short chart windows empty, and event-age metrics include the feed delay.

Optional Kafka support uses `KAFKA_BROKER`, `KAFKA_USERNAME`, and `KAFKA_PASSWORD` for SASL/PLAIN over TLS. Create `stocks-trades` and `stocks-quotes` topics first; automatic topic creation is disabled. This is a best-effort secondary copy, not a durable ingestion queue. Kafka failures do not undo a successful ClickHouse insert.

## Behavior and limits

- Subscriptions are sent after authentication succeeds. The default three symbols keep the demo manageable; the watchlist does not change the upstream subscription.
- Each table flushes at 1,000 rows or every two seconds. Four synchronous inserts can run concurrently, with compression enabled. Counters increase only after ClickHouse acknowledges an insert.
- The queue holds at most 100 waiting batches. Queue overflow, pause, and heap pressure above 512 MiB discard records, counted in `droppedMessages` (a legacy field name). Failed ClickHouse inserts increment `failedRecords`; they are not retried. This demo does not guarantee lossless delivery or replay after reconnect.
- Shutdown stops ingestion and attempts to drain buffered inserts for up to 30 seconds. A forced exit can lose pending data.
- The watchlist polls once per second. Chart windows are 5 minutes, 30 minutes, 1 hour, and 1 day; empty charts keep polling. Queries calculate change from the first **ingested** trade of the current New York calendar day, not the official open or previous close. Volume covers only ingested ticks and does not filter sale conditions or apply corrections.
- `(t, q)` breaks timestamp ties for open/close/latest prices. `t` is the feed's SIP timestamp in milliseconds. The dashboard's latency value is event age, not just ClickHouse insert latency.
- Quiet sessions, market holidays, missing entitlements, or no recent data can leave the dashboard empty. Check the admin status and selected subscription before troubleshooting ClickHouse.

## Verify

```sh
npm test
npm run typecheck
npm run build
npm run test:smoke
```

The smoke test needs a running ClickHouse server and permission to create/drop a temporary database. It ingests representative trade/quote events through the real batching code and checks all seven dashboard queries, including sequence ties and indicators above 255. It removes its database on completion. Unit/API tests need no external service. Kafka and a live Massive subscription require separate validation with appropriate credentials.

Stop the backend with Ctrl-C. If you started local ClickHouse with the commands above, stop it from the same example directory:

```sh
clickhousectl local server stop stock-demo
```
