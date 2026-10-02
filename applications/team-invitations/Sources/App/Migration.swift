import Fluent
import FluentPostgresDriver
import Vapor

struct InitialSchema: AsyncMigration {
  func prepare(on database: any Database) async throws {
    try await database.schema("users", space: "invites").id().field("name", .string, .required)
      .create()
    try await database.schema("teams", space: "invites").id().field("name", .string, .required)
      .field("admin_id", .uuid, .required, .references("users", "id")).create()
    try await database.schema("memberships", space: "invites").id()
      .field("team_id", .uuid, .required, .references("teams", "id"))
      .field("user_id", .uuid, .required, .references("users", "id"))
      .field("created_at", .datetime, .required)
      .unique(on: "team_id", "user_id").unique(on: "id", "team_id", "user_id").create()
    try await database.schema("invitations", space: "invites").id()
      .field("team_id", .uuid, .required, .references("teams", "id"))
      .field("recipient_id", .uuid, .required, .references("users", "id"))
      .field("token_digest", .string, .required).unique(on: "token_digest")
      .field("status", .string, .required)
      .field("created_at", .datetime, .required).field("expires_at", .datetime, .required)
      .field("accepted_at", .datetime).field("revoked_at", .datetime)
      .field("accepted_membership_id", .uuid).create()
    guard let sql = database as? any SQLDatabase else {
      throw Abort(.internalServerError, reason: "Postgres SQL database required")
    }
    // Static constraints/grants complement Fluent's native schema migrations.
    let statements: [SQLQueryString] = [
      "ALTER TABLE invites.users ADD CHECK (length(name) BETWEEN 1 AND 80)",
      "ALTER TABLE invites.teams ADD CHECK (length(name) BETWEEN 1 AND 80)",
      "ALTER TABLE invites.invitations ADD CHECK (length(token_digest)=64 AND token_digest ~ '^[0-9a-f]{64}$')",
      "ALTER TABLE invites.invitations ADD CHECK (expires_at > created_at AND expires_at <= created_at + interval '1 day')",
      """
      ALTER TABLE invites.invitations ADD CHECK (
        (status='pending' AND accepted_at IS NULL AND revoked_at IS NULL AND accepted_membership_id IS NULL) OR
        (status='accepted' AND accepted_at IS NOT NULL AND revoked_at IS NULL AND accepted_membership_id IS NOT NULL) OR
        (status='revoked' AND accepted_at IS NULL AND revoked_at IS NOT NULL AND accepted_membership_id IS NULL))
      """,
      """
      ALTER TABLE invites.invitations ADD CONSTRAINT accepted_membership_matches_recipient
        FOREIGN KEY (accepted_membership_id,team_id,recipient_id)
        REFERENCES invites.memberships(id,team_id,user_id) DEFERRABLE INITIALLY DEFERRED
      """,
      "CREATE INDEX invitations_team_cursor ON invites.invitations(team_id,id)",
      "CREATE INDEX memberships_user_cursor ON invites.memberships(user_id,id)",
      "GRANT SELECT ON invites.users, invites.teams, invites.invitations, invites.memberships TO invites_app",
      "GRANT INSERT ON invites.invitations, invites.memberships TO invites_app",
      "GRANT UPDATE (id) ON invites.teams TO invites_app",
      "GRANT UPDATE (status,accepted_at,revoked_at,accepted_membership_id) ON invites.invitations TO invites_app",
    ]
    for statement in statements { try await sql.raw(statement).run() }
  }
  func revert(on database: any Database) async throws {
    try await database.schema("invitations", space: "invites").delete()
    try await database.schema("memberships", space: "invites").delete()
    try await database.schema("teams", space: "invites").delete()
    try await database.schema("users", space: "invites").delete()
  }
}
