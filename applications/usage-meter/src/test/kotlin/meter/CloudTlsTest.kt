package meter

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable
import java.net.InetAddress
import java.sql.SQLException
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

@EnabledIfEnvironmentVariable(named = "RUN_CLOUD_TESTS", matches = "1")
class CloudTlsTest {
    @Test fun postgresUsesTlsAndRejectsWrongCaAndHostname() {
        pgSource().connection.use { connection ->
            connection.createStatement().use { statement ->
                statement.executeQuery("SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()").use {
                    assertTrue(it.next() && it.getBoolean(1))
                }
            }
        }
        val address = InetAddress.getByName(required("PGHOST")).hostAddress
        for (source in listOf(pgSource(ca = required("TEST_WRONG_CA")), pgSource(host = address))) {
            val failure = assertFailsWith<SQLException> { source.connection.use {} }
            val descriptions = generateSequence<Throwable>(failure) { it.cause }.joinToString(" ") { it.message ?: "" }.lowercase()
            assertTrue(descriptions.contains("certificate") || descriptions.contains("hostname"))
        }
        println("Verified Cloud Postgres TLS; unrelated CA and wrong hostname rejected")
    }
}
