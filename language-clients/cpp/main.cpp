// A tour of the official ClickHouse C++ client (clickhouse-cpp) against ClickHouse Cloud:
// connect over the native protocol with TLS, create a table, insert typed blocks, run a
// parameterized query, stream rows back, map an aggregate into structs, handle a server error.
#include <clickhouse/client.h>

#include <chrono>
#include <cinttypes>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <map>
#include <optional>
#include <stdexcept>
#include <string>
#include <vector>

using namespace clickhouse;

namespace {

constexpr size_t kTotalRows = 10000;
constexpr size_t kBatchSize = 1000;

// 2026-01-01T00:00:00.000Z as Unix milliseconds; the base for every recorded_at.
constexpr int64_t kEpochBaseMs = 1767225600000LL;

const char* const kSites[] = {"amsterdam", "berlin", "london", "madrid", "paris"};

std::string RequireEnv(const char* name) {
    const char* value = std::getenv(name);
    if (value == nullptr || *value == '\0') {
        throw std::runtime_error(std::string("missing required environment variable ") + name);
    }
    return value;
}

// One row of the dataset, generated from its index so every language produces identical rows.
struct Reading {
    UUID reading_id;
    int64_t recorded_at_ms;
    std::string device_id;
    std::string site;
    double temp_c;
    std::optional<double> humidity_pct;
    uint8_t battery_pct;
    std::vector<std::string> tags;
    std::map<std::string, std::string> attributes;
};

Reading MakeReading(int64_t i) {
    Reading r;
    // UUID is a pair of the high and low 64 bits, so 00000000-0000-4000-8000-<i as 12 hex>
    // is {0x0000000000004000, 0x8000000000000000 | i}.
    r.reading_id = UUID{0x0000000000004000ULL, 0x8000000000000000ULL | static_cast<uint64_t>(i)};
    r.recorded_at_ms = kEpochBaseMs + i * 1000 + (i * 37) % 1000;

    char device[16];
    std::snprintf(device, sizeof(device), "device-%02d", static_cast<int>(i % 50));
    r.device_id = device;
    r.site = kSites[(i % 50) % 5];

    r.temp_c = 15.0 + static_cast<double>((i * 7919) % 1997) / 100.0;
    if (i % 10 != 0) {
        r.humidity_pct = 30.0 + static_cast<double>((i * 104729) % 6000) / 100.0;
    }
    r.battery_pct = static_cast<uint8_t>(100 - (i % 101));

    if (i % 3 == 0) {
        r.tags = {"calibrated"};
    } else if (i % 3 == 1) {
        r.tags = {"calibrated", "outdoor"};
    }

    r.attributes["firmware"] = "1." + std::to_string(i % 4);
    r.attributes["model"] = (i % 2 == 0) ? "tx-100" : "tx-200";
    return r;
}

// LowCardinality(String) arrives as a plain ColumnLowCardinality, so As<ColumnLowCardinalityT<>>
// returns null; GetItem() reads the dictionary entry without the destructive Wrap() cast.
std::string ReadString(const ColumnRef& column, size_t row) {
    if (auto plain = column->As<ColumnString>()) {
        return std::string(plain->At(row));
    }
    return std::string(column->AsStrict<ColumnLowCardinality>()->GetItem(row).get<std::string_view>());
}

Reading ReadReading(const Block& block, size_t row) {
    Reading r;
    r.reading_id = block[0]->AsStrict<ColumnUUID>()->At(row);
    r.recorded_at_ms = block[1]->AsStrict<ColumnDateTime64>()->At(row);
    r.device_id = ReadString(block[2], row);
    r.site = ReadString(block[3], row);
    r.temp_c = block[4]->AsStrict<ColumnFloat64>()->At(row);

    // Nullable(T) arrives as ColumnNullable; the typed view has to be built from Nested().
    auto humidity = block[5]->AsStrict<ColumnNullable>();
    if (!humidity->IsNull(row)) {
        r.humidity_pct = humidity->Nested()->AsStrict<ColumnFloat64>()->At(row);
    }

    r.battery_pct = block[6]->AsStrict<ColumnUInt8>()->At(row);

    // Array(T) and Map(K, V) hand back one row as a column slice.
    auto tags = block[7]->AsStrict<ColumnArray>()->GetAsColumnTyped<ColumnString>(row);
    for (size_t i = 0; i < tags->Size(); ++i) {
        r.tags.emplace_back(tags->At(i));
    }
    auto attributes = block[8]->AsStrict<ColumnMap>()->GetAsColumn(row)->AsStrict<ColumnTuple>();
    auto keys = (*attributes)[0]->AsStrict<ColumnString>();
    auto values = (*attributes)[1]->AsStrict<ColumnString>();
    for (size_t i = 0; i < keys->Size(); ++i) {
        r.attributes.emplace(keys->At(i), values->At(i));
    }
    return r;
}

// Step 6 maps each aggregate row onto this.
struct SiteStats {
    std::string site;
    uint64_t readings;
    double avg_temp_c;
    double max_temp_c;
};

int Run() {
    const std::string host = RequireEnv("CLICKHOUSE_HOST");
    const std::string port = RequireEnv("CLICKHOUSE_NATIVE_PORT");
    const std::string user = RequireEnv("CLICKHOUSE_USER");
    const std::string password = RequireEnv("CLICKHOUSE_PASSWORD");
    const std::string database = RequireEnv("CLICKHOUSE_DATABASE");
    const std::string table = database + ".readings_cpp";

    // 1. Connect and ping.
    Client client(ClientOptions()
                      .SetHost(host)
                      .SetPort(static_cast<uint16_t>(std::stoi(port)))
                      .SetUser(user)
                      .SetPassword(password)
                      .SetDefaultDatabase(database)
                      // An empty SSLOptions is enough: it verifies against the system CA store.
                      .SetSSLOptions(ClientOptions::SSLOptions())
                      // Cloud services can take a while to wake from idle.
                      .SetConnectionConnectTimeout(std::chrono::seconds(30)));
    client.Ping();

    std::string version;
    client.Select("SELECT version()", [&](const Block& block) {
        for (size_t i = 0; i < block.GetRowCount(); ++i) {
            version = block[0]->AsStrict<ColumnString>()->At(i);
        }
    });
    std::printf("1 connect: ok, server version %s\n", version.c_str());

    // 2. Create the table.
    client.Execute("DROP TABLE IF EXISTS " + table);
    client.Execute("CREATE TABLE " + table + R"((
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
ORDER BY (site, device_id, recorded_at))");
    std::printf("2 create table: ok\n");

    // 3. Insert 10,000 rows as 10 native blocks of typed columns.
    size_t batches = 0;
    for (size_t offset = 0; offset < kTotalRows; offset += kBatchSize) {
        auto reading_id = std::make_shared<ColumnUUID>();
        auto recorded_at = std::make_shared<ColumnDateTime64>(3, "UTC");
        auto device_id = std::make_shared<ColumnLowCardinalityT<ColumnString>>();
        auto site = std::make_shared<ColumnLowCardinalityT<ColumnString>>();
        auto temp_c = std::make_shared<ColumnFloat64>();
        auto humidity_pct = std::make_shared<ColumnNullableT<ColumnFloat64>>();
        auto battery_pct = std::make_shared<ColumnUInt8>();
        auto tags = std::make_shared<ColumnArrayT<ColumnString>>(std::make_shared<ColumnString>());
        auto attributes = std::make_shared<ColumnMapT<ColumnString, ColumnString>>(
            std::make_shared<ColumnString>(), std::make_shared<ColumnString>());

        for (size_t i = offset; i < offset + kBatchSize; ++i) {
            const Reading r = MakeReading(static_cast<int64_t>(i));
            reading_id->Append(r.reading_id);
            recorded_at->Append(r.recorded_at_ms);
            device_id->Append(r.device_id);
            site->Append(r.site);
            temp_c->Append(r.temp_c);
            humidity_pct->Append(r.humidity_pct);
            battery_pct->Append(r.battery_pct);
            tags->Append(r.tags);
            attributes->Append(r.attributes);
        }

        Block block;
        block.AppendColumn("reading_id", reading_id);
        block.AppendColumn("recorded_at", recorded_at);
        block.AppendColumn("device_id", device_id);
        block.AppendColumn("site", site);
        block.AppendColumn("temp_c", temp_c);
        block.AppendColumn("humidity_pct", humidity_pct);
        block.AppendColumn("battery_pct", battery_pct);
        block.AppendColumn("tags", tags);
        block.AppendColumn("attributes", attributes);

        // Insert() derives "INSERT INTO <table> (<block column names>) VALUES" from the block.
        client.Insert(table, block);
        ++batches;
    }
    std::printf("3 insert: %zu rows in %zu batches\n", kTotalRows, batches);

    // 4. Parameterized query. Query::SetParam sends real server-side query parameters, so the
    // values never touch the SQL text. Every parameter is carried as a string and cast by the
    // server according to the type declared in the {name:Type} placeholder.
    const std::string device = "device-07";
    const std::string min_temp = "30.0";
    uint64_t matches = 0;
    Query counted("SELECT count() FROM " + table +
                  " WHERE device_id = {device:String} AND temp_c > {min_temp:Float64}");
    counted.SetParam("device", device);
    counted.SetParam("min_temp", min_temp);
    counted.OnData([&](const Block& block) {
        for (size_t i = 0; i < block.GetRowCount(); ++i) {
            matches = block[0]->AsStrict<ColumnUInt64>()->At(i);
        }
    });
    client.Select(counted);
    std::printf("4 parameterized query: %" PRIu64 " readings for %s above %s C\n", matches,
                device.c_str(), min_temp.c_str());

    // 5. Stream every row back. Select() invokes the callback once per block as it arrives,
    // so nothing accumulates client side.
    uint64_t rows = 0;
    uint64_t battery_total = 0;
    uint64_t humidity_nulls = 0;
    uint64_t tag_total = 0;
    client.Select("SELECT * FROM " + table + " ORDER BY recorded_at", [&](const Block& block) {
        for (size_t i = 0; i < block.GetRowCount(); ++i) {
            const Reading r = ReadReading(block, i);
            ++rows;
            battery_total += r.battery_pct;
            humidity_nulls += r.humidity_pct.has_value() ? 0 : 1;
            tag_total += r.tags.size();
        }
    });
    std::printf("5 stream: %" PRIu64 " rows, battery total %" PRIu64 ", humidity null in %" PRIu64
                " rows, %" PRIu64 " tags\n",
                rows, battery_total, humidity_nulls, tag_total);

    // 6. Aggregate into typed results.
    std::vector<SiteStats> stats;
    client.Select("SELECT site, count() AS readings,"
                  " round(avg(temp_c), 2) AS avg_temp_c,"
                  " round(max(temp_c), 2) AS max_temp_c"
                  " FROM " + table + " GROUP BY site ORDER BY site",
                  [&](const Block& block) {
                      for (size_t i = 0; i < block.GetRowCount(); ++i) {
                          stats.push_back(SiteStats{
                              ReadString(block[0], i),
                              block[1]->AsStrict<ColumnUInt64>()->At(i),
                              block[2]->AsStrict<ColumnFloat64>()->At(i),
                              block[3]->AsStrict<ColumnFloat64>()->At(i),
                          });
                      }
                  });
    std::printf("6 aggregate: site readings avg_temp_c max_temp_c\n");
    for (const SiteStats& s : stats) {
        std::printf("6 aggregate: %s %" PRIu64 " %.2f %.2f\n", s.site.c_str(), s.readings,
                    s.avg_temp_c, s.max_temp_c);
    }

    // 7. Handle a server error. ClientOptions::rethrow_exceptions defaults to true, so server
    // errors surface as ServerException rather than going to an OnException callback.
    try {
        client.Select("SELECT count() FROM " + database + ".no_such_table_cpp",
                      [](const Block&) {});
        std::fprintf(stderr, "expected the query on a missing table to fail\n");
        return 1;
    } catch (const ServerException& e) {
        std::printf("7 error: server error code %d\n", e.GetCode());
    }

    return 0;
}

}  // namespace

int main() {
    try {
        return Run();
    } catch (const std::exception& e) {
        std::fprintf(stderr, "client tour failed: %s\n", e.what());
        return 1;
    }
}
