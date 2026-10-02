import Fluent
import FluentPostgresDriver
import Vapor

private func required(_ name: String) throws -> String {
  guard let value = Environment.get(name), !value.isEmpty else {
    throw Abort(.internalServerError, reason: "Missing configuration")
  }
  return value
}
public func configure(
  _ app: Application, schemaMode: Bool, wrongHostname: Bool = false, tlsProbe: Bool = false
) throws {
  app.logger.logLevel = .warning
  let user = try required("PGUSER")
  guard user == (schemaMode ? "invites_migrator" : "invites_app") else {
    throw Abort(.internalServerError)
  }
  let host = try required("PGHOST")
  guard let port = Int(try required("PGPORT")), (1...65535).contains(port) else {
    throw Abort(.internalServerError)
  }
  var tls = TLSConfiguration.makeClientConfiguration()
  tls.certificateVerification = .fullVerification
  tls.trustRoots = .file(try required("PGSSLROOTCERT"))
  var core = PostgresConnection.Configuration(
    host: host, port: port, username: user,
    password: try required("PGPASSWORD"), database: try required("PGDATABASE"),
    tls: .require(try NIOSSLContext(configuration: tls)))
  core.options.tlsServerName = wrongHostname ? "mismatch.invalid" : host
  core.options.connectTimeout = .seconds(5)
  core.options.additionalStartupParameters = [
    ("application_name", "team-invitations"),
    (
      "options",
      "-c search_path=invites -c timezone=UTC -c statement_timeout=15000"
        + (schemaMode ? " -c role=invites_owner" : "")
    ),
  ]
  // Two explicit event loops in entrypoint × two connections per loop = at most four.
  app.databases.use(
    .postgres(
      configuration: SQLPostgresConfiguration(coreConfiguration: core),
      maxConnectionsPerEventLoop: 2, connectionPoolTimeout: .seconds(10), sqlLogLevel: .trace),
    as: .psql)
  app.routes.defaultMaxBodySize = "4kb"
  app.http.server.configuration.hostname = "127.0.0.1"
  if let value = Environment.get("PORT") {
    guard let port = Int(value), (1...65535).contains(port) else {
      throw Abort(.internalServerError)
    }
    app.http.server.configuration.port = port
  } else {
    app.http.server.configuration.port = 3000
  }
  let encoder = JSONEncoder()
  encoder.dateEncodingStrategy = .iso8601
  ContentConfiguration.global.use(encoder: encoder, for: .json)
  app.middleware = .init()
  app.middleware.use(PublicErrors())
  if schemaMode {
    app.migrations.add(InitialSchema())
    app.asyncCommands.use(SeedCommand(), as: "seed")
  } else {
    app.asyncCommands.use(TLSCheckCommand(), as: "tls-check")
    if !tlsProbe { try routes(app) }
  }
}
private struct PublicErrors: AsyncMiddleware {
  func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
    do { return try await next.respond(to: request) } catch {
      let status: HTTPResponseStatus
      if let abort = error as? any AbortError {
        status = abort.status
      } else if error is DecodingError {
        status = .badRequest
      } else if let database = error as? any DatabaseError, database.isConstraintFailure {
        status = .conflict
      } else {
        status = .serviceUnavailable
      }
      struct ErrorBody: Content { let error: String }
      let body = ErrorBody(
        error: status == .serviceUnavailable ? "Service unavailable" : status.reasonPhrase)
      return try await body.encodeResponse(status: status, for: request)
    }
  }
}
private func routes(_ app: Application) throws {
  let authenticator = try TokenAuthenticator(json: required("USER_TOKENS"))
  app.lifecycle.use(ValidateConfiguredUsers(ids: Array(authenticator.tokens.keys)))
  let scoped = app.grouped(authenticator, Actor.guardMiddleware())
  scoped.post("teams", ":id", "invitations") { request async throws -> Response in
    let input = try request.content.decode(IssueInput.self)
    return try await issue(request, teamID: pathID(request), input: input).encodeResponse(
      status: .created, for: request)
  }
  scoped.post("invitations", ":id", "accept") { request async throws -> Response in
    let input = try request.content.decode(AcceptInput.self)
    let (created, member) = try await accept(request, id: pathID(request), input: input)
    return try await member.encodeResponse(status: created ? .created : .ok, for: request)
  }
  scoped.post("invitations", ":id", "revoke") { request async throws -> InvitationView in
    _ = try request.content.decode(RevokeInput.self)
    return try await revoke(request, id: pathID(request))
  }
  scoped.get("teams", ":id", "invitations") { request async throws -> InvitationPage in
    try await invitationList(request, teamID: pathID(request), input: PageInput(request))
  }
  scoped.get("memberships") { request async throws -> MembershipPage in
    try await membershipList(request, input: PageInput(request))
  }
}

private struct ValidateConfiguredUsers: LifecycleHandler {
  let ids: [UUID]
  func willBootAsync(_ application: Application) async throws {
    for id in ids {
      guard try await InviteUser.find(id, on: application.db) != nil else {
        throw Abort(.internalServerError, reason: "Configured user missing")
      }
    }
  }
}
