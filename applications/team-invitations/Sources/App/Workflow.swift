import Fluent
import FluentPostgresDriver
import Vapor

private func sql(_ database: any Database) throws -> any SQLDatabase {
  guard let sql = database as? any SQLDatabase else { throw Abort(.serviceUnavailable) }
  return sql
}
private func databaseTime(_ database: any Database) async throws -> Date {
  guard let row = try await sql(database).raw("SELECT clock_timestamp() AS now").first()
  else { throw Abort(.serviceUnavailable) }
  return try row.decode(column: "now", as: Date.self)
}
func issue(_ request: Request, teamID: UUID, input: IssueInput) async throws -> IssuedInvitation {
  let actor = try request.auth.require(Actor.self)
  let secret = newInvitationSecret()
  let tokenDigest = digest(secret)
  return try await request.db.transaction { transaction in
    // Scope and lock the team before using its immutable administrator identity.
    guard
      try await sql(transaction).raw(
        """
        SELECT id FROM invites.teams
        WHERE id=\(bind: teamID) AND admin_id=\(bind: actor.id) FOR UPDATE
        """
      ).first() != nil
    else { throw Abort(.notFound) }
    guard try await InviteUser.find(input.recipientUserId, on: transaction) != nil else {
      throw Abort(.notFound)
    }
    guard
      try await Membership.query(on: transaction).filter(\.$teamID == teamID)
        .filter(\.$userID == input.recipientUserId).first() == nil
    else { throw Abort(.conflict, reason: "Already a team member") }
    let now = try await databaseTime(transaction)
    let invitation = Invitation(
      teamID: teamID, recipientID: input.recipientUserId, digest: tokenDigest,
      now: now, expires: now.addingTimeInterval(Double(input.ttlMinutes * 60)))
    try await invitation.create(on: transaction)
    return try IssuedInvitation(invitation: InvitationView(invitation), secret: secret)
  }
}
func accept(_ request: Request, id: UUID, input: AcceptInput) async throws -> (Bool, MembershipView)
{
  let actor = try request.auth.require(Actor.self)
  let candidate = digest(input.secret)
  return try await request.db.transaction { transaction in
    guard
      try await sql(transaction).raw(
        """
        SELECT id FROM invites.invitations
        WHERE id=\(bind: id) AND recipient_id=\(bind: actor.id) FOR UPDATE
        """
      ).first() != nil
    else { throw Abort(.notFound) }
    guard let invitation = try await Invitation.find(id, on: transaction),
      matchingDigest(candidate, invitation.tokenDigest)
    else { throw Abort(.notFound) }
    // Matching consumed replay precedes pending-expiry checks, even after expiry.
    if invitation.status == "accepted" {
      guard let memberID = invitation.acceptedMembershipID,
        let membership = try await Membership.find(memberID, on: transaction)
      else { throw Abort(.serviceUnavailable) }
      return (false, try MembershipView(membership))
    }
    guard invitation.status == "pending" else {
      throw Abort(.conflict, reason: "Invitation revoked")
    }
    // clock_timestamp(), not transaction-start/current app time, after acquiring the lock.
    let now = try await databaseTime(transaction)
    guard now < invitation.expiresAt else { throw Abort(.gone, reason: "Invitation expired") }
    guard
      try await Membership.query(on: transaction).filter(\.$teamID == invitation.teamID)
        .filter(\.$userID == actor.id).first() == nil
    else { throw Abort(.conflict, reason: "Already a team member") }
    let membership = Membership(
      id: UUID(), teamID: invitation.teamID, userID: actor.id, createdAt: now)
    invitation.status = "accepted"
    invitation.acceptedAt = now
    invitation.acceptedMembershipID = try membership.requireID()
    try await invitation.update(on: transaction)
    // Deferred composite FK permits state-first insertion; commit enforces same team/recipient.
    try await membership.create(on: transaction)
    return (true, try MembershipView(membership))
  }
}
func revoke(_ request: Request, id: UUID) async throws -> InvitationView {
  let actor = try request.auth.require(Actor.self)
  return try await request.db.transaction { transaction in
    // Accept and revoke lock exactly the same invitation row; neither locks another invite.
    guard
      try await sql(transaction).raw(
        """
        SELECT i.id FROM invites.invitations AS i
        JOIN invites.teams AS t ON t.id=i.team_id
        WHERE i.id=\(bind: id) AND t.admin_id=\(bind: actor.id) FOR UPDATE OF i
        """
      ).first() != nil
    else { throw Abort(.notFound) }
    guard let invitation = try await Invitation.find(id, on: transaction) else {
      throw Abort(.notFound)
    }
    guard invitation.status != "accepted" else {
      throw Abort(.conflict, reason: "Acceptance cannot be revoked")
    }
    if invitation.status == "pending" {
      invitation.status = "revoked"
      invitation.revokedAt = try await databaseTime(transaction)
      try await invitation.update(on: transaction)
    }
    return try InvitationView(invitation)
  }
}
func invitationList(_ request: Request, teamID: UUID, input: PageInput) async throws
  -> InvitationPage
{
  let actor = try request.auth.require(Actor.self)
  guard
    try await Team.query(on: request.db).filter(\.$id == teamID).filter(\.$adminID == actor.id)
      .first() != nil
  else { throw Abort(.notFound) }
  let query = Invitation.query(on: request.db).filter(\.$teamID == teamID).sort(\.$id).limit(
    input.limit + 1)
  if let after = input.after { query.filter(\.$id > after) }
  let models = try await query.all()
  let items = try models.prefix(input.limit).map(InvitationView.init)
  return InvitationPage(items: items, nextAfter: models.count > input.limit ? items.last?.id : nil)
}
func membershipList(_ request: Request, input: PageInput) async throws -> MembershipPage {
  let actor = try request.auth.require(Actor.self)
  let query = Membership.query(on: request.db).filter(\.$userID == actor.id).sort(\.$id).limit(
    input.limit + 1)
  if let after = input.after { query.filter(\.$id > after) }
  let models = try await query.all()
  let items = try models.prefix(input.limit).map(MembershipView.init)
  return MembershipPage(items: items, nextAfter: models.count > input.limit ? items.last?.id : nil)
}
