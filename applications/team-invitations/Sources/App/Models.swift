import Fluent
import Vapor

// Models deliberately do not conform to Content: digest/state internals stay private.
final class InviteUser: Model, @unchecked Sendable {
  static let schema = "users"
  static let space: String? = "invites"
  @ID(key: .id) var id: UUID?
  @Field(key: "name") var name: String
  init() {}
  init(id: UUID, name: String) {
    self.id = id
    self.name = name
  }
}
final class Team: Model, @unchecked Sendable {
  static let schema = "teams"
  static let space: String? = "invites"
  @ID(key: .id) var id: UUID?
  @Field(key: "name") var name: String
  @Field(key: "admin_id") var adminID: UUID
  init() {}
  init(id: UUID, name: String, adminID: UUID) {
    self.id = id
    self.name = name
    self.adminID = adminID
  }
}
final class Membership: Model, @unchecked Sendable {
  static let schema = "memberships"
  static let space: String? = "invites"
  @ID(key: .id) var id: UUID?
  @Field(key: "team_id") var teamID: UUID
  @Field(key: "user_id") var userID: UUID
  @Field(key: "created_at") var createdAt: Date
  init() {}
  init(id: UUID, teamID: UUID, userID: UUID, createdAt: Date) {
    self.id = id
    self.teamID = teamID
    self.userID = userID
    self.createdAt = createdAt
  }
}
final class Invitation: Model, @unchecked Sendable {
  static let schema = "invitations"
  static let space: String? = "invites"
  @ID(key: .id) var id: UUID?
  @Field(key: "team_id") var teamID: UUID
  @Field(key: "recipient_id") var recipientID: UUID
  @Field(key: "token_digest") var tokenDigest: String
  @Field(key: "status") var status: String
  @Field(key: "created_at") var createdAt: Date
  @Field(key: "expires_at") var expiresAt: Date
  @OptionalField(key: "accepted_at") var acceptedAt: Date?
  @OptionalField(key: "revoked_at") var revokedAt: Date?
  @OptionalField(key: "accepted_membership_id") var acceptedMembershipID: UUID?
  init() {}
  init(teamID: UUID, recipientID: UUID, digest: String, now: Date, expires: Date) {
    self.id = UUID()
    self.teamID = teamID
    self.recipientID = recipientID
    self.tokenDigest = digest
    self.status = "pending"
    self.createdAt = now
    self.expiresAt = expires
  }
}
struct InvitationView: Content, Sendable {
  let id: UUID
  let teamID: UUID
  let recipientUserID: UUID
  let status: String
  let createdAt: Date
  let expiresAt: Date
  init(_ model: Invitation) throws {
    self.id = try model.requireID()
    self.teamID = model.teamID
    self.recipientUserID = model.recipientID
    self.status = model.status
    self.createdAt = model.createdAt
    self.expiresAt = model.expiresAt
  }
}
struct MembershipView: Content, Equatable, Sendable {
  let id: UUID
  let teamID: UUID
  let userID: UUID
  let createdAt: Date
  init(_ model: Membership) throws {
    self.id = try model.requireID()
    self.teamID = model.teamID
    self.userID = model.userID
    self.createdAt = model.createdAt
  }
}
struct IssuedInvitation: Content, Sendable {
  let invitation: InvitationView
  // This is the only response that contains the raw invitation secret.
  let secret: String
}
struct InvitationPage: Content, Sendable {
  let items: [InvitationView]
  let nextAfter: UUID?
}
struct MembershipPage: Content, Sendable {
  let items: [MembershipView]
  let nextAfter: UUID?
}
