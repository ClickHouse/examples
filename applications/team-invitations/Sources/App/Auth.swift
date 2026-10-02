import Vapor

struct Actor: Authenticatable, Sendable { let id: UUID }
struct TokenAuthenticator: AsyncBearerAuthenticator {
  let tokens: [UUID: String]
  init(json: String) throws {
    let input = try JSONDecoder().decode([String: String].self, from: Data(json.utf8))
    guard (1...20).contains(input.count), Set(input.values).count == input.count else {
      throw Abort(.internalServerError)
    }
    var tokens: [UUID: String] = [:]
    for (key, value) in input {
      guard key.count == 36, let id = UUID(uuidString: key), (32...256).contains(value.utf8.count),
        value.utf8.allSatisfy({
          (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45
            || $0 == 95
        }),
        tokens[id] == nil
      else { throw Abort(.internalServerError) }
      tokens[id] = digest(value)
    }
    self.tokens = tokens
  }
  func authenticate(bearer: BearerAuthorization, for request: Request) async throws {
    let candidate = digest(bearer.token)
    for (id, expected) in self.tokens {
      if matchingDigest(candidate, expected) { request.auth.login(Actor(id: id)) }
    }
  }
}
