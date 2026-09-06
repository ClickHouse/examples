using System.Globalization;
using ClickHouse.Driver;
using ClickHouse.Driver.ADO;
using ClickHouse.Driver.ADO.Parameters;
using ClickHouse.Driver.Utility;
using ClientTour;

const string Lang = "dotnet";
const int TotalRows = 10_000;
const int BatchSize = 1_000;

var inv = CultureInfo.InvariantCulture;
var database = Env("CLICKHOUSE_DATABASE");
var table = $"{database}.readings_{Lang}";

var settings = new ClickHouseClientSettings
{
    Host = Env("CLICKHOUSE_HOST"),
    Port = ushort.Parse(Env("CLICKHOUSE_HTTPS_PORT"), inv),
    Protocol = "https",
    Username = Env("CLICKHOUSE_USER"),
    Password = Env("CLICKHOUSE_PASSWORD"),
    Database = database,
};

// ClickHouseClient is thread safe and meant to be a long-lived singleton: it owns the
// pooled HttpClient, the compression codecs and the POCO schema caches.
using var client = new ClickHouseClient(settings);

// POCO types are registered once; registration builds and caches the binary
// serializer (insert) and the column-to-property map (read).
client.RegisterBinaryInsertType<Reading>();
client.RegisterPocoType<SiteSummary>();

// 1. Connect and ping.
var version = (string)(await client.ExecuteScalarAsync("SELECT version()"))!;
Console.WriteLine($"1 connect: ok, server version {version}");

// 2. Create the table.
await client.ExecuteNonQueryAsync($"DROP TABLE IF EXISTS {table}");
await client.ExecuteNonQueryAsync($$"""
    CREATE TABLE {{table}}
    (
        reading_id   UUID,
        recorded_at  DateTime64(3, 'UTC'),
        device_id    LowCardinality(String),
        site         LowCardinality(String),
        temp_c       Float64,
        humidity_pct Nullable(Float64),
        battery_pct  UInt8,
        tags         Array(String),
        attributes   Map(String, String)
    )
    ENGINE = MergeTree
    ORDER BY (site, device_id, recorded_at)
    """);
Console.WriteLine("2 create table: ok");

// 3. Insert 10,000 typed rows in 10 batches.
// InsertBinaryAsync streams the POCOs as RowBinary; the driver reads the table schema
// once (cached) to pick the column encoders, so no SQL literals are built.
var insertOptions = new InsertOptions { BatchSize = BatchSize, MaxDegreeOfParallelism = 1 };
long inserted = 0;
var batches = 0;
for (var offset = 0; offset < TotalRows; offset += BatchSize)
{
    inserted += await client.InsertBinaryAsync(table, Batch(offset, BatchSize), insertOptions);
    batches++;
}
Console.WriteLine($"3 insert: {inserted} rows in {batches} batches");

// 4. Parameterized query, bound server side as {name:Type}.
var queryParams = new ClickHouseParameterCollection();
queryParams.AddParameter("device", "device-07");
queryParams.AddParameter("min_temp", 30.0);
var matches = (ulong)(await client.ExecuteScalarAsync(
    $"SELECT count() FROM {table} WHERE device_id = {{device:String}} AND temp_c > {{min_temp:Float64}}",
    queryParams))!;
Console.WriteLine($"4 parameterized query: {matches} readings for device-07 above {30.0.ToString("F1", inv)} C");

// 5. Stream every row back, decoding each column into its CLR type.
// ClickHouseDataReader reads forward over the still-open HTTP response, so only the
// current row is materialised.
long rowCount = 0, batteryTotal = 0, humidityNulls = 0, tagCount = 0;
await using (var reader = await client.ExecuteReaderAsync($"SELECT * FROM {table} ORDER BY recorded_at"))
{
    var idOrd = reader.GetOrdinal("reading_id");
    var atOrd = reader.GetOrdinal("recorded_at");
    var deviceOrd = reader.GetOrdinal("device_id");
    var siteOrd = reader.GetOrdinal("site");
    var tempOrd = reader.GetOrdinal("temp_c");
    var humidityOrd = reader.GetOrdinal("humidity_pct");
    var batteryOrd = reader.GetOrdinal("battery_pct");
    var tagsOrd = reader.GetOrdinal("tags");
    var attributesOrd = reader.GetOrdinal("attributes");

    while (await reader.ReadAsync())
    {
        _ = reader.GetGuid(idOrd);
        _ = reader.GetDateTime(atOrd);
        _ = reader.GetString(deviceOrd);
        _ = reader.GetString(siteOrd);
        _ = reader.GetDouble(tempOrd);
        _ = reader.GetFieldValue<Dictionary<string, string>>(attributesOrd);

        if (reader.IsDBNull(humidityOrd)) humidityNulls++; else _ = reader.GetDouble(humidityOrd);
        batteryTotal += reader.GetByte(batteryOrd);
        tagCount += reader.GetFieldValue<string[]>(tagsOrd).Length;
        rowCount++;
    }
}
Console.WriteLine(
    $"5 stream: {rowCount} rows, battery total {batteryTotal}, " +
    $"humidity null in {humidityNulls} rows, {tagCount} tags");

// 6. Aggregate into typed results. QueryAsync<T> maps each row onto the POCO.
Console.WriteLine("6 aggregate: site readings avg_temp_c max_temp_c");
var aggregate = client.QueryAsync<SiteSummary>($"""
    SELECT site, count() AS readings,
           round(avg(temp_c), 2) AS avg_temp_c,
           round(max(temp_c), 2) AS max_temp_c
    FROM {table}
    GROUP BY site ORDER BY site
    """);
await foreach (var row in aggregate)
{
    Console.WriteLine(
        $"6 aggregate: {row.Site} {row.Readings} " +
        $"{row.AvgTempC.ToString("F2", inv)} {row.MaxTempC.ToString("F2", inv)}");
}

// 7. Handle a server error. ClickHouseServerException derives from DbException, so the
// ClickHouse error code arrives in the inherited ErrorCode property.
try
{
    await client.ExecuteScalarAsync($"SELECT count() FROM {database}.no_such_table_{Lang}");
    Console.Error.WriteLine("expected the unknown-table query to fail");
    return 1;
}
catch (ClickHouseServerException ex)
{
    Console.WriteLine($"7 error: server error code {ex.ErrorCode}");
}

return 0;

static string Env(string name) =>
    Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
        ? value
        : throw new InvalidOperationException($"missing required environment variable {name}");

// Rows are generated from the index with integer arithmetic and a single division, so
// every language in the tour produces bit-identical values.
static IEnumerable<Reading> Batch(int offset, int count)
{
    string[] sites = ["amsterdam", "berlin", "london", "madrid", "paris"];
    var epoch = new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc);

    for (var i = offset; i < offset + count; i++)
    {
        yield return new Reading
        {
            ReadingId = Guid.ParseExact($"00000000-0000-4000-8000-{i:x12}", "D"),
            RecordedAt = epoch.AddMilliseconds(i * 1000L + i * 37L % 1000),
            DeviceId = $"device-{i % 50:D2}",
            Site = sites[i % 50 % 5],
            TempC = 15.0 + i * 7919L % 1997 / 100.0,
            HumidityPct = i % 10 == 0 ? null : 30.0 + i * 104729L % 6000 / 100.0,
            BatteryPct = (byte)(100 - i % 101),
            Tags = (i % 3) switch
            {
                0 => ["calibrated"],
                1 => ["calibrated", "outdoor"],
                _ => [],
            },
            Attributes = new Dictionary<string, string>
            {
                ["firmware"] = $"1.{i % 4}",
                ["model"] = i % 2 == 0 ? "tx-100" : "tx-200",
            },
        };
    }
}
