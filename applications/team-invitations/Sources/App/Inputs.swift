import Vapor

private struct AnyKey: CodingKey {
  let stringValue: String
  let intValue: Int? = nil
  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}
private func rejectUnknown(_ decoder: any Decoder, allowed: Set<String>) throws {
  let keys = try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue)
  guard Set(keys).isSubset(of: allowed) else {
    throw Abort(.badRequest, reason: "Unknown input field")
  }
}
struct IssueInput: Content, Sendable {
  let recipientUserId: UUID
  let ttlMinutes: Int
  enum CodingKeys: String, CodingKey { case recipientUserId, ttlMinutes }
  init(from decoder: any Decoder) throws {
    try rejectUnknown(decoder, allowed: ["recipientUserId", "ttlMinutes"])
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.recipientUserId = try values.decode(UUID.self, forKey: .recipientUserId)
    self.ttlMinutes = try values.decodeIfPresent(Int.self, forKey: .ttlMinutes) ?? 60
    guard (1...1440).contains(self.ttlMinutes) else {
      throw Abort(.badRequest, reason: "TTL must be 1–1440 minutes")
    }
  }
}
struct AcceptInput: Content, Sendable {
  let secret: String
  enum CodingKeys: String, CodingKey { case secret }
  init(from decoder: any Decoder) throws {
    try rejectUnknown(decoder, allowed: ["secret"])
    self.secret = try decoder.container(keyedBy: CodingKeys.self).decode(
      String.self, forKey: .secret)
    guard
      self.secret.utf8.count == 43
        && self.secret.utf8.allSatisfy({ byte in
          (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte)
            || byte == 45 || byte == 95
        })
    else { throw Abort(.badRequest, reason: "Secret must be 43 base64url characters") }
  }
}
struct RevokeInput: Content, Sendable {
  init(from decoder: any Decoder) throws { try rejectUnknown(decoder, allowed: []) }
  func encode(to encoder: any Encoder) throws { _ = encoder.container(keyedBy: AnyKey.self) }
}
struct PageInput: Sendable {
  let limit: Int
  let after: UUID?
  init(_ request: Request) throws {
    let raw: String? = try request.query.get(at: "limit")
    if let raw {
      guard !raw.isEmpty, raw.utf8.allSatisfy({ (48...57).contains($0) }), let limit = Int(raw),
        (1...50).contains(limit)
      else { throw Abort(.badRequest, reason: "Limit must be 1–50") }
      self.limit = limit
    } else {
      self.limit = 20
    }
    let cursor: String? = try request.query.get(at: "after")
    if let cursor {
      guard cursor.count == 36, let after = UUID(uuidString: cursor) else {
        throw Abort(.badRequest, reason: "Invalid cursor UUID")
      }
      self.after = after
    } else {
      self.after = nil
    }
  }
}
func pathID(_ request: Request) throws -> UUID {
  guard let raw = request.parameters.get("id"), raw.count == 36, let value = UUID(uuidString: raw)
  else { throw Abort(.badRequest, reason: "Invalid UUID") }
  return value
}
