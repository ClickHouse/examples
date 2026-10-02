package meter

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.jetbrains.exposed.v1.core.*
import org.jetbrains.exposed.v1.jdbc.*
import org.jetbrains.exposed.v1.jdbc.transactions.transaction
import org.jetbrains.exposed.v1.core.ResultRow
import java.time.Clock
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.util.UUID
import javax.sql.DataSource

class Store(source: DataSource, private val clock: Clock = Clock.systemUTC()) {
    private val db = Database.connect(source)
    private val work = Dispatchers.IO.limitedParallelism(5)

    suspend fun verifyAccounts(ids: List<UUID>) = withContext(work) {
        transaction(db) {
            ids.forEach { id -> require(Accounts.selectAll().where { Accounts.id eq id }.count() == 1L) }
        }
    }
    suspend fun consume(account: UUID, input: Consumption): Pair<Boolean, Accepted> = withContext(work) {
        validate(input)
        transaction(db) {
            maxAttempts = 1
            // One lock serializes quota decisions and request-ID replay for this account,
            // including two requests spanning UTC midnight. No ClickHouse dependency.
            val owner = Accounts.selectAll().where { Accounts.id eq account }.forUpdate().single()
            val existing = Events.selectAll().where {
                (Events.accountId eq account) and (Events.requestId eq input.requestId)
            }.singleOrNull()
            if (existing != null) {
                if (existing[Events.feature] != input.feature || existing[Events.units].toInt() != input.units)
                    throw ApiError(409, "Request ID already has different data")
                return@transaction false to accepted(existing)
            }
            val acceptedAt = clock.instant().atOffset(ZoneOffset.UTC)
            val day = acceptedAt.toLocalDate()
            val counter = Counters.selectAll().where {
                (Counters.accountId eq account) and (Counters.day eq day)
            }.singleOrNull()
            val used = counter?.get(Counters.used) ?: 0
            val quota = owner[Accounts.dailyQuota]
            if (input.units > quota - used) throw ApiError(429, "Daily quota exhausted")
            if (counter == null) {
                Counters.insert {
                    it[accountId] = account; it[Counters.day] = day; it[Counters.used] = input.units
                }
            } else {
                Counters.update({ (Counters.accountId eq account) and (Counters.day eq day) }) {
                    it[Counters.used] = used + input.units
                }
            }
            val id = UUID.randomUUID()
            val remaining = quota - used - input.units
            Events.insert {
                it[Events.id] = id; it[accountId] = account; it[requestId] = input.requestId
                it[Events.day] = day; it[feature] = input.feature; it[units] = input.units.toShort()
                it[Events.remaining] = remaining; it[created] = acceptedAt
            }
            true to Accepted(id.toString(), input.requestId, day.toString(), input.feature, input.units, remaining)
        }
    }
    suspend fun inspect(account: UUID, requestId: String): Accepted = withContext(work) {
        transaction(db) {
            val row = Events.selectAll().where {
                (Events.accountId eq account) and (Events.requestId eq requestId)
            }.singleOrNull() ?: throw ApiError(404, "Event not found")
            accepted(row)
        }
    }
    suspend fun quota(account: UUID): Quota = withContext(work) {
        transaction(db) {
            // One SQL statement observes quota and counter consistently.
            val day = LocalDate.now(clock)
            val row = Accounts.join(Counters, JoinType.LEFT, Accounts.id, Counters.accountId,
                additionalConstraint = { Counters.day eq day })
                .selectAll().where { Accounts.id eq account }.single()
            val quota = row[Accounts.dailyQuota]
            val used = row.getOrNull(Counters.used) ?: 0
            Quota(account.toString(), day.toString(), quota, used, quota - used)
        }
    }
    private fun accepted(row: ResultRow) = Accepted(
        row[Events.id].toString(), row[Events.requestId], row[Events.day].toString(),
        row[Events.feature], row[Events.units].toInt(), row[Events.remaining],
    )
}
