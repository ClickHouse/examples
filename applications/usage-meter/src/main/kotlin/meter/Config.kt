package meter

import com.zaxxer.hikari.HikariConfig
import com.zaxxer.hikari.HikariDataSource
import kotlinx.serialization.json.Json
import org.postgresql.ds.PGSimpleDataSource
import java.net.URI
import java.security.MessageDigest
import java.util.UUID

fun required(name: String): String = System.getenv(name)?.takeIf { it.isNotBlank() }
    ?: error("Missing $name")

fun pgSource(host: String = required("PGHOST"), ca: String = required("PGSSLROOTCERT")): PGSimpleDataSource {
    require(required("PGUSER") == "usage_app") { "Runtime requires usage_app" }
    return PGSimpleDataSource().apply {
        serverNames = arrayOf(host)
        portNumbers = intArrayOf((System.getenv("PGPORT") ?: "5432").toInt().also { require(it in 1..65535) })
        databaseName = required("PGDATABASE")
        user = required("PGUSER")
        password = required("PGPASSWORD")
        sslMode = "verify-full"
        sslRootCert = ca
        connectTimeout = 5
        socketTimeout = 25
        options = "-csearch_path=usage -ctimezone=UTC -cstatement_timeout=20000"
    }
}
fun pgPool() = HikariDataSource(HikariConfig().apply {
    dataSource = pgSource()
    maximumPoolSize = 5
    minimumIdle = 0
    connectionTimeout = 15_000
    validationTimeout = 5_000
    poolName = "usage-postgres"
})
fun checkedEndpoint(value: String): String {
    val uri = URI(value)
    require(uri.scheme == "https" && uri.host != null && uri.rawUserInfo == null)
    require(uri.rawQuery == null && uri.rawFragment == null && uri.path in listOf("", "/"))
    return value
}
class TokenScopes(raw: String) {
    private val entries: List<Pair<ByteArray, UUID>>
    init {
        val parsed = Json.decodeFromString<Map<String, String>>(raw)
        require(parsed.size in 1..20)
        require(parsed.values.toSet().size == parsed.size)
        entries = parsed.map { (id, token) ->
            require(token.length in 32..256 && token.none { it.isWhitespace() })
            hash(token) to UUID.fromString(id)
        }
    }
    val accountIds: List<UUID> get() = entries.map { it.second }
    fun account(token: String): UUID? {
        if (token.length > 256) return null
        val provided = hash(token)
        var found: UUID? = null
        entries.forEach { (expected, id) -> if (MessageDigest.isEqual(expected, provided)) found = id }
        return found
    }
    private fun hash(value: String) = MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8))
}
