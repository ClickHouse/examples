# ClickHouse language clients: one tour, eight official clients

The same small program written eight times, once for each official ClickHouse
client library, all running against one ClickHouse Cloud service. Each version
connects over TLS, creates a table, inserts 10,000 typed rows in batches, runs a
parameterized query, streams every row back, maps an aggregation into typed
records, and handles a server error. Every implementation prints the same
output, so you can read two languages side by side and see exactly how each
client expresses the same idea.

The contract all implementations follow is in [SPEC.md](./SPEC.md). The
reference output is [expected-output.txt](./expected-output.txt).

## The clients

| Directory | Language | Client | Protocol | Notes |
| --- | --- | --- | --- | --- |
| [dotnet](./dotnet/README.md) | C# / .NET | [`ClickHouse.Driver`](https://clickhouse.com/docs/integrations/csharp) (NuGet) | HTTPS | Successor to `ClickHouse.Client`. High-level `ClickHouseClient` API plus ADO.NET. |
| [java-client](./java-client/README.md) | Java | [`com.clickhouse:client-v2`](https://clickhouse.com/docs/integrations/language-clients/java/client) | HTTPS | The recommended Java client. POJO inserts, RowBinary reads. |
| [java-jdbc](./java-jdbc/README.md) | Java | [`com.clickhouse:clickhouse-jdbc`](https://clickhouse.com/docs/integrations/language-clients/java/jdbc) | HTTPS | Plain JDBC on top of Client V2, for frameworks that expect a JDBC driver. |
| [rust](./rust/README.md) | Rust | [`clickhouse`](https://clickhouse.com/docs/integrations/rust) crate | HTTPS (RowBinary) | serde row derive, cursor streaming, client-side binding. |
| [go](./go/README.md) | Go | [`clickhouse-go/v2`](https://clickhouse.com/docs/integrations/go) | Native TCP over TLS | Native API with batches; `database/sql` also available. |
| [cpp](./cpp/README.md) | C++ | [`clickhouse-cpp`](https://clickhouse.com/docs/integrations/language-clients/cpp) | Native TCP over TLS | Column-oriented `Block` API. |
| [python](./python/README.md) | Python | [`clickhouse-connect`](https://clickhouse.com/docs/integrations/python) | HTTPS | Row and columnar inserts, streaming, DataFrames if you want them. |
| [nodejs](./nodejs/README.md) | Node.js / TypeScript | [`@clickhouse/client`](https://clickhouse.com/docs/integrations/javascript) | HTTPS | Zero dependencies. `@clickhouse/client-web` for browsers and Workers. |

## What each tour does

| Step | Output line | What it exercises |
| --- | --- | --- |
| 1 | `1 connect: ok, server version ...` | TLS connection settings, a first round trip |
| 2 | `2 create table: ok` | DDL from the client; the schema uses UUID, DateTime64(3), LowCardinality, Nullable, Array, Map |
| 3 | `3 insert: 10000 rows in 10 batches` | The client's typed or binary insert path, batched |
| 4 | `4 parameterized query: 48 readings ...` | Parameter binding, server-side where the client supports it |
| 5 | `5 stream: 10000 rows, ...` | Streaming or cursor reads, deserializing every type natively |
| 6 | `6 aggregate: ...` | Mapping result rows into typed records |
| 7 | `7 error: server error code 60` | The client's exception type and how it exposes the ClickHouse error code |

The dataset is generated in code from the row index, so there is nothing to
download and every language produces identical rows.

## Prerequisites

- A ClickHouse Cloud account. [Sign up at clickhouse.com/cloud](https://clickhouse.com/cloud)
  to start a free trial with $300 in credits. This example creates a chargeable
  service; the trial credits cover it comfortably, and you stop it when you are done.
- [`clickhousectl`](https://clickhouse.com/docs/products/cloud/features/cli),
  the ClickHouse Cloud CLI, plus `jq`, `curl`, and `openssl`.
- The toolchain for whichever language you want to run. Each subdirectory's
  README lists its own.

Install the CLI if you do not have it:

```sh
curl -fsSL https://clickhouse.com/cli | sh
export PATH="$HOME/.local/bin:$PATH"
clickhousectl --version
```

## 1. Authenticate from this directory

`clickhousectl` stores credentials relative to the directory you log in from, so
run everything below from `examples/language-clients`.

Create an **Admin-role Cloud API key** for your organization by following the
[API key guide](https://clickhouse.com/docs/products/cloud/features/admin-features/api/openapi),
then log in:

```sh
cd examples/language-clients
clickhousectl cloud auth login --interactive
clickhousectl cloud auth status
clickhousectl cloud org list
```

Status should show API-key authentication with read/write scope. OAuth login is
read-only and cannot create services or users.

## 2. Create the service and the application user

```sh
scripts/cloud.sh create
scripts/cloud.sh setup
```

`create` provisions one fixed 8 GiB replica in AWS `eu-west-1` with idle scaling
on and a five minute idle timeout. It allows connections only from your current
public IP, never from `0.0.0.0/0`. Set `CLIENT_TOUR_IP`, `CLIENT_TOUR_REGION`,
`CLIENT_TOUR_PROVIDER`, `CLIENT_TOUR_SERVICE_NAME`, or `CLIENT_TOUR_ORG_ID` to
change these. The equivalent CLI command is:

```sh
clickhousectl cloud service create \
  --name language-clients-example --provider aws --region eu-west-1 \
  --min-replica-memory-gb 8 --max-replica-memory-gb 8 --num-replicas 1 \
  --idle-scaling true --idle-timeout-minutes 5 \
  --ip-allow "$(curl -4fsS https://api.ipify.org)/32" --json
```

`setup` waits for the service to be running, creates the `client_tour`
database, generates a password, writes `.env`, then creates the
`client_tour_app` user with `SELECT, INSERT, CREATE TABLE, DROP TABLE` on that
database only. Each tour creates and drops its own table, which is why the
application user has DDL rights. The programs never use the `default`
administrator or your Cloud API key.

`.env`, the service ID in `.cloud-service.json`, and the one-time create
response are gitignored and written with mode `0600`. Setup is resumable. If
`create` times out, check `clickhousectl cloud service list` before retrying and
adopt the service with `scripts/cloud.sh recover <service-id>` rather than
creating a second one.

If you would rather provision by hand or reuse an existing service, copy
`.env.example` to `.env` and fill it in. The programs only read those six
variables.

## 3. Run a tour

Every implementation is run the same way. Export the variables from `.env`,
then call its `run.sh`, which builds if needed:

```sh
set -a; source .env; set +a
./rust/run.sh
```

You should see:

```
1 connect: ok, server version 26.2.1.641
2 create table: ok
3 insert: 10000 rows in 10 batches
4 parameterized query: 48 readings for device-07 above 30.0 C
5 stream: 10000 rows, battery total 500050, humidity null in 1000 rows, 10000 tags
6 aggregate: site readings avg_temp_c max_temp_c
6 aggregate: amsterdam 2000 24.98 34.96
6 aggregate: berlin 2000 24.99 34.96
6 aggregate: london 2000 24.99 34.96
6 aggregate: madrid 2000 24.99 34.96
6 aggregate: paris 2000 24.99 34.96
7 error: server error code 60
```

Run every implementation you have a toolchain for and check them against the
reference output:

```sh
scripts/verify.sh            # all
scripts/verify.sh go python  # some
```

Each implementation writes to its own table (`client_tour.readings_<lang>`), so
they can run concurrently.

## 4. Stop the service

```sh
scripts/cloud.sh stop
```

Idle scaling pauses compute after the idle timeout anyway, but stopping is
explicit. The script retains the service and its storage; delete it from the
Cloud console or with `clickhousectl cloud service delete <id>` when you no
longer need it.

## How the clients differ

The spec is the same, but the clients are not, and the differences are the
interesting part. Each subdirectory's README has a Notes section; the highlights:

- **Parameter binding.** Node.js, Python, Go, .NET, Java Client V2, Rust
  (`Query::param`), and C++ (`Query::SetParam`) all send `{name:Type}`
  parameters to the server. JDBC has no named parameters, so it uses standard `?`
  placeholders, and its "prepared statement" is client-side substitution rather
  than a wire-protocol bind.
- **Error codes.** Most clients expose the ClickHouse error code as a field on
  their exception type: .NET inherits it as `ErrorCode`, Java Client V2 has
  `ServerException.getCode()`, JDBC populates `SQLException.getErrorCode()`, Go has
  `clickhouse.Exception.Code`, Python has `DatabaseError.code`, Node.js has
  `ClickHouseError.code`, C++ has `ServerException::GetCode()`. The Rust crate only
  exposes the message, so the tour parses `Code: 60` out of it.
- **Protocol.** The HTTP clients (.NET, Java, Rust, Python, Node.js) use port
  8443. The native protocol clients (Go and C++) use port 9440 and speak
  ClickHouse's binary protocol directly.
- **Insert shape.** Row-oriented clients take a list of objects: POCOs in .NET,
  POJOs in Java, serde structs in Rust, structs with `ch` tags in Go, row lists in
  Python, JSON objects in Node.js. C++ builds column-oriented blocks, which is how
  ClickHouse stores data and is the fastest path.
- **Traps the agents hit while writing these.** Java Client V2's `queryAll()`
  rewraps `ServerException`, so use `query()` to read the code. .NET read models
  need settable properties, so they cannot be `record` types. The Rust crate maps
  `Map(K, V)` to `Vec<(K, V)>`, not a `HashMap`. clickhouse-cpp's documented
  FetchContent flow needs the vendored abseil include directory added by hand.

## Layout

```
language-clients/
  README.md             this file
  SPEC.md               the contract every implementation follows
  expected-output.txt   reference output
  scripts/cloud.sh      provision, set up, and stop the Cloud service with clickhousectl
  scripts/verify.sh     run implementations and diff against the reference
  sql/                  shared DDL applied by setup
  <lang>/               one directory per client, each with README.md and run.sh
```
