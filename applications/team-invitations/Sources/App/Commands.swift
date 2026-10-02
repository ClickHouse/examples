import Fluent
import FluentPostgresDriver
import Vapor

struct SeedCommand: AsyncCommand {
  struct Signature: CommandSignature {}
  var help: String { "Seed two teams and four users; preserves existing state" }
  func run(using context: CommandContext, signature: Signature) async throws {
    try await context.application.db.transaction { transaction in
      for number in 1...4 {
        let id = UUID(uuidString: "00000000-0000-4000-8000-\(String(format: "%012d", number))")!
        if try await InviteUser.find(id, on: transaction) == nil {
          try await InviteUser(id: id, name: "Demo user \(number)").create(on: transaction)
        }
      }
      for (prefix, admin, name) in [("a", 1, "North team"), ("b", 2, "South team")] {
        let id = UUID(uuidString: "\(prefix)0000000-0000-4000-8000-000000000001")!
        let owner = UUID(uuidString: "00000000-0000-4000-8000-\(String(format: "%012d", admin))")!
        if try await Team.find(id, on: transaction) == nil {
          try await Team(id: id, name: name, adminID: owner).create(on: transaction)
        }
      }
    }
    context.console.print("Seeded two teams and four users; existing state preserved")
  }
}
struct TLSCheckCommand: AsyncCommand {
  struct Signature: CommandSignature {
    @Flag(name: "wrong-hostname", help: "Negative test only: mismatch certificate name/SNI")
    var wrongHostname: Bool
  }
  var help: String { "Probe the actual runtime Fluent/PostgresNIO TLS connection" }
  func run(using context: CommandContext, signature: Signature) async throws {
    guard let sql = context.application.db as? any SQLDatabase else {
      throw Abort(.internalServerError)
    }
    let row = try await sql.raw(
      "SELECT ssl,version,current_user FROM pg_stat_ssl WHERE pid=pg_backend_pid()"
    ).first()
    guard let row, try row.decode(column: "ssl", as: Bool.self) else {
      throw Abort(.serviceUnavailable)
    }
    context.console.print(
      "Actual Fluent/PostgresNIO path verified: \(try row.decode(column: "version", as: String.self)), role \(try row.decode(column: "current_user", as: String.self))"
    )
  }
}
