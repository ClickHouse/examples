package meter

import com.clickhouse.client.api.Client
import com.clickhouse.client.api.query.QuerySettings
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.Clock
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import java.util.UUID
import java.util.concurrent.TimeUnit

fun reportDates(from: String?, to: String?, clock: Clock = Clock.systemUTC()): Pair<LocalDate, LocalDate> {
    val today = LocalDate.now(clock)
    val start = try { from?.let(LocalDate::parse) ?: today.minusDays(6) } catch (_: Exception) { throw ApiError(400, "Invalid report dates") }
    val end = try { to?.let(LocalDate::parse) ?: today } catch (_: Exception) { throw ApiError(400, "Invalid report dates") }
    if (start > end || start < today.minusDays(30) || end > today)
        throw ApiError(400, "Reports cover at most the last 31 UTC days")
    return start to end
}
class Analytics : AutoCloseable {
    private val client = Client.Builder()
        .addEndpoint(checkedEndpoint(required("CLICKHOUSE_URL")))
        .setUsername(required("CLICKHOUSE_USER").also { require(it == "usage_reports") })
        .setPassword(required("CLICKHOUSE_PASSWORD"))
        .setMaxConnections(2)
        .useAsyncRequests(false)
        .setMaxRetries(0)
        .setConnectionRequestTimeout(5, ChronoUnit.SECONDS)
        .setConnectTimeout(5, ChronoUnit.SECONDS)
        .setSocketTimeout(10, ChronoUnit.SECONDS)
        .build()
    private val work = Dispatchers.IO.limitedParallelism(2)
    suspend fun report(account: UUID, from: LocalDate, to: LocalDate): Report = withContext(work) {
        val sql = """
            SELECT usage_day, feature, sum(units) AS units, count() AS events
            FROM default.cdc_usage_events FINAL
            WHERE account_id = {account:UUID}
              AND usage_day BETWEEN {from:Date32} AND {to:Date32}
              AND _peerdb_is_deleted = 0
            GROUP BY usage_day, feature
            ORDER BY usage_day, feature
            LIMIT 93
        """.trimIndent()
        val settings = QuerySettings().setMaxExecutionTime(5)
            .serverSetting("max_rows_to_read", "1000000")
            .serverSetting("max_bytes_to_read", "100000000")
            .serverSetting("max_result_rows", "93")
            .serverSetting("result_overflow_mode", "throw")
            .serverSetting("timeout_before_checking_execution_speed", "0")
        val params = mapOf<String, Any>("account" to account.toString(), "from" to from, "to" to to)
        val rows = mutableListOf<FeatureTotal>()
        // The client executes synchronously on this bounded IO dispatcher.
        // Future.get is an additional wait cap, not an end-to-end HTTP deadline.
        client.query(sql, params, settings).get(15, TimeUnit.SECONDS).use { response ->
            val reader = client.newBinaryFormatReader(response)
            while (reader.hasNext()) {
                reader.next()
                rows += FeatureTotal(reader.getLocalDate("usage_day").toString(), reader.getString("feature"),
                    reader.getLong("units"), reader.getLong("events"))
            }
        }
        val daily = rows.groupBy { it.usageDay }.map { (day, features) ->
            DailyTotal(day, features.sumOf { it.units }, features.sumOf { it.events })
        }
        Report(account.toString(), from.toString(), to.toString(), daily, rows)
    }
    override fun close() = client.close()
}
