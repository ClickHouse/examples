package meter

import kotlinx.serialization.Serializable
import org.jetbrains.exposed.v1.core.Table
import org.jetbrains.exposed.v1.core.java.javaUUID
import org.jetbrains.exposed.v1.javatime.date
import org.jetbrains.exposed.v1.javatime.timestampWithTimeZone

object Accounts : Table("usage.accounts") {
    val id = javaUUID("id")
    val name = text("name")
    val dailyQuota = integer("daily_quota")
    override val primaryKey = PrimaryKey(id)
}
object Counters : Table("usage.daily_counters") {
    val accountId = javaUUID("account_id")
    val day = date("usage_day")
    val used = integer("used_units")
    override val primaryKey = PrimaryKey(accountId, day)
}
object Events : Table("usage.events") {
    val id = javaUUID("event_id")
    val accountId = javaUUID("account_id")
    val requestId = text("request_id")
    val day = date("usage_day")
    val feature = text("feature")
    val units = short("units")
    val remaining = integer("remaining_units")
    val created = timestampWithTimeZone("created_at")
    override val primaryKey = PrimaryKey(id)
}
@Serializable data class Consumption(val requestId: String, val feature: String, val units: Int)
@Serializable data class Accepted(
    val eventId: String, val requestId: String, val usageDay: String,
    val feature: String, val units: Int, val remainingAtAcceptance: Int,
)
@Serializable data class Quota(val accountId: String, val usageDay: String, val quota: Int, val used: Int, val remaining: Int)
@Serializable data class FeatureTotal(val usageDay: String, val feature: String, val units: Long, val events: Long)
@Serializable data class DailyTotal(val usageDay: String, val units: Long, val events: Long)
@Serializable data class Report(
    val accountId: String, val from: String, val to: String,
    val daily: List<DailyTotal>, val features: List<FeatureTotal>,
    val consistency: String = "eventual", val quotaAuthority: String = "postgres",
)
@Serializable data class ErrorResponse(val error: String)
class ApiError(val status: Int, message: String) : RuntimeException(message)

fun validate(input: Consumption) {
    if (!input.requestId.matches(Regex("[A-Za-z0-9._-]{1,64}"))) throw ApiError(400, "Invalid request ID")
    if (input.feature !in setOf("api", "export", "storage")) throw ApiError(400, "Unknown feature")
    if (input.units !in 1..1000) throw ApiError(400, "Units must be between 1 and 1000")
}
