package meter

import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.util.UUID
import kotlin.test.*

@EnabledIfEnvironmentVariable(named = "RUN_CLOUD_TESTS", matches = "1")
class CloudClockTest {
    @Test fun replayAfterUtcMidnightKeepsOriginalDayAndDebitsOnce() = runBlocking {
        val account = UUID.fromString("00000000-0000-4000-8000-000000000002")
        val yesterday = LocalDate.now(Clock.systemUTC()).minusDays(1)
        val before = yesterday.atTime(23, 59, 59).toInstant(ZoneOffset.UTC)
        val after = yesterday.plusDays(1).atStartOfDay().toInstant(ZoneOffset.UTC)
        val input = Consumption("clock-${UUID.randomUUID()}", "storage", 2)
        pgPool().use { pool ->
            val original = Store(pool, Clock.fixed(before, ZoneOffset.UTC))
            val nextDay = Store(pool, Clock.fixed(after, ZoneOffset.UTC))
            val currentBefore = nextDay.quota(account)
            val (created, first) = original.consume(account, input)
            assertTrue(created)
            assertEquals(yesterday.toString(), first.usageDay)
            val (recreated, replay) = nextDay.consume(account, input)
            assertFalse(recreated)
            assertEquals(first, replay)
            assertEquals(currentBefore, nextDay.quota(account))
            pool.connection.use { connection ->
                connection.prepareStatement("SELECT usage_day, created_at FROM usage.events WHERE event_id = ?").use {
                    it.setObject(1, UUID.fromString(first.eventId))
                    it.executeQuery().use { row ->
                        assertTrue(row.next())
                        assertEquals(yesterday, row.getObject(1, LocalDate::class.java))
                        assertEquals(before, row.getTimestamp(2).toInstant())
                    }
                }
            }
            println("UTC-midnight replay retained original day, timestamp, ID and one debit; current-day counter unchanged")
        }
    }
}
