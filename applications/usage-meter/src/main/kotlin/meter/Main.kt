package meter

import io.ktor.http.HttpStatusCode
import io.ktor.serialization.kotlinx.json.json
import io.ktor.server.application.*
import io.ktor.server.auth.*
import io.ktor.server.engine.embeddedServer
import io.ktor.server.netty.Netty
import io.ktor.server.plugins.BadRequestException
import io.ktor.server.plugins.PayloadTooLargeException
import io.ktor.server.plugins.bodylimit.RequestBodyLimit
import io.ktor.server.plugins.contentnegotiation.ContentNegotiation
import io.ktor.server.plugins.statuspages.StatusPages
import io.ktor.server.request.receive
import io.ktor.server.response.respond
import io.ktor.server.routing.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json

fun main() {
    try {
        val pool = pgPool()
        val store = Store(pool)
        val tokens = TokenScopes(required("ACCOUNT_TOKENS"))
        runBlocking { store.verifyAccounts(tokens.accountIds) }
        val analytics = Analytics()
        val port = (System.getenv("PORT") ?: "3000").toInt().also { require(it in 1..65535) }
        val server = embeddedServer(Netty, host = "127.0.0.1", port = port) {
            install(ContentNegotiation) { json(Json { ignoreUnknownKeys = false; encodeDefaults = true }) }
            install(RequestBodyLimit) { bodyLimit { 4096L } }
            install(StatusPages) {
                exception<ApiError> { call, cause -> call.respond(HttpStatusCode.fromValue(cause.status), ErrorResponse(cause.message!!)) }
                exception<PayloadTooLargeException> { call, _ -> call.respond(HttpStatusCode.PayloadTooLarge, ErrorResponse("Body exceeds 4096 bytes")) }
                exception<BadRequestException> { call, _ -> call.respond(HttpStatusCode.BadRequest, ErrorResponse("Invalid request")) }
                exception<SerializationException> { call, _ -> call.respond(HttpStatusCode.BadRequest, ErrorResponse("Invalid JSON")) }
                exception<Throwable> { call, cause ->
                    if (cause is CancellationException) throw cause
                    call.respond(HttpStatusCode.ServiceUnavailable, ErrorResponse("Service unavailable; operational quota still comes from Postgres"))
                }
            }
            install(Authentication) {
                bearer("account") {
                    authenticate { credential -> tokens.account(credential.token)?.let { UserIdPrincipal(it.toString()) } }
                }
            }
            routing {
                authenticate("account") {
                    post("/usage") {
                        val account = java.util.UUID.fromString(call.principal<UserIdPrincipal>()!!.name)
                        val (created, result) = store.consume(account, call.receive<Consumption>())
                        call.respond(if (created) HttpStatusCode.Created else HttpStatusCode.OK, result)
                    }
                    get("/events/{requestId}") {
                        val account = java.util.UUID.fromString(call.principal<UserIdPrincipal>()!!.name)
                        call.respond(store.inspect(account, call.parameters["requestId"]!!))
                    }
                    get("/quota") {
                        val account = java.util.UUID.fromString(call.principal<UserIdPrincipal>()!!.name)
                        call.respond(store.quota(account))
                    }
                    get("/reports") {
                        if (call.request.queryParameters.names().any { it !in setOf("from", "to") }) throw ApiError(400, "Unknown report parameter")
                        val account = java.util.UUID.fromString(call.principal<UserIdPrincipal>()!!.name)
                        val (from, to) = reportDates(call.request.queryParameters["from"], call.request.queryParameters["to"])
                        call.respond(analytics.report(account, from, to))
                    }
                }
            }
        }
        Runtime.getRuntime().addShutdownHook(Thread { server.stop(500, 3000); analytics.close(); pool.close() })
        server.start(wait = true)
    } catch (_: Exception) {
        System.err.println("Usage meter failed to start; check configuration, role, TLS and database readiness")
        kotlin.system.exitProcess(1)
    }
}
