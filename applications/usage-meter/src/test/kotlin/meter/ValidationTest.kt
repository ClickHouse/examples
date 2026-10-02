package meter

import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Test
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import kotlin.test.*

class ValidationTest {
    @Test fun boundedConsumptionAndIdentity() {
        validate(Consumption("request-1", "api", 1000))
        listOf(Consumption("has spaces", "api", 1), Consumption("nul\u0000", "api", 1),
            Consumption("valid", "unknown", 1), Consumption("valid", "api", 0),
            Consumption("valid", "api", 1001)).forEach { assertFailsWith<ApiError> { validate(it) } }
        assertFails { Json.decodeFromString<Consumption>("""{"requestId":"r","feature":"api","units":1,"accountId":"foreign"}""") }
    }
    @Test fun reportsCannotWidenTheDateWindow() {
        val clock = Clock.fixed(Instant.parse("2026-10-02T00:00:00Z"), ZoneOffset.UTC)
        assertEquals("2026-09-02", reportDates("2026-09-02", "2026-10-02", clock).first.toString())
        for ((from, to) in listOf("2026-09-01" to "2026-10-02", "2026-10-02" to "2026-10-03", "bad" to "2026-10-02"))
            assertFailsWith<ApiError> { reportDates(from, to, clock) }
    }
    @Test fun tokensCannotBeSharedAcrossAccounts() {
        val token = "a".repeat(32)
        assertFails { TokenScopes("""{"00000000-0000-4000-8000-000000000001":"$token","00000000-0000-4000-8000-000000000002":"$token"}""") }
        val scopes = TokenScopes("""{"00000000-0000-4000-8000-000000000001":"$token"}""")
        assertEquals("00000000-0000-4000-8000-000000000001", scopes.account(token).toString())
        assertNull(scopes.account("wrong"))
    }
    @Test fun analyticalEndpointRequiresTrustedHttps() {
        assertEquals("https://example.com:8443", checkedEndpoint("https://example.com:8443"))
        for (url in listOf("http://example.com", "https://user:password@example.com", "https://example.com/?query=x"))
            assertFails { checkedEndpoint(url) }
    }
}
