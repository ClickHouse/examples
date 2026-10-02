import Vapor
import XCTest

@testable import App

final class InputTests: XCTestCase {
  private let decoder = JSONDecoder()
  func testIssueBoundsAndUnknownFields() throws {
    let recipient = "00000000-0000-4000-8000-000000000003"
    let valid = "{\"recipientUserId\":\"\(recipient)\"}"
    XCTAssertEqual(try decoder.decode(IssueInput.self, from: Data(valid.utf8)).ttlMinutes, 60)
    for suffix in [
      ",\"ttlMinutes\":0", ",\"ttlMinutes\":1441", ",\"ttlMinutes\":1.5", ",\"teamId\":\"forged\"",
    ] {
      XCTAssertThrowsError(
        try decoder.decode(
          IssueInput.self, from: Data("{\"recipientUserId\":\"\(recipient)\"\(suffix)}".utf8)))
    }
  }
  func testSecretShapeAndEmptyRevokeDTO() throws {
    let secret = String(repeating: "A", count: 43)
    XCTAssertNoThrow(
      try decoder.decode(AcceptInput.self, from: Data("{\"secret\":\"\(secret)\"}".utf8)))
    for invalid in [
      String(repeating: "A", count: 42), String(repeating: "A", count: 44),
      String(repeating: "A", count: 42) + "=", String(repeating: "é", count: 43),
    ] {
      XCTAssertThrowsError(
        try decoder.decode(AcceptInput.self, from: Data("{\"secret\":\"\(invalid)\"}".utf8)))
    }
    XCTAssertNoThrow(try decoder.decode(RevokeInput.self, from: Data("{}".utf8)))
    XCTAssertThrowsError(try decoder.decode(RevokeInput.self, from: Data("{\"owner\":1}".utf8)))
  }
  func testRandomSecretAndDigest() {
    let first = newInvitationSecret()
    let second = newInvitationSecret()
    XCTAssertEqual(first.count, 43)
    XCTAssertNotEqual(first, second)
    XCTAssertEqual(
      digest("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    XCTAssertTrue(matchingDigest(digest(first), digest(first)))
    XCTAssertFalse(matchingDigest(digest(first), digest(second)))
    XCTAssertFalse(matchingDigest("short", digest(first)))
  }
  func testCredentialMappingRejectsAmbiguousOrWeakIdentities() throws {
    let id = "00000000-0000-4000-8000-000000000001"
    XCTAssertThrowsError(try TokenAuthenticator(json: "{}"))
    XCTAssertThrowsError(try TokenAuthenticator(json: "{\"\(id)\":\"short\"}"))
    let token = String(repeating: "A", count: 32)
    let authenticator = try TokenAuthenticator(json: "{\"\(id)\":\"\(token)\"}")
    XCTAssertEqual(authenticator.tokens[UUID(uuidString: id)!], digest(token))
    XCTAssertThrowsError(
      try TokenAuthenticator(
        json: "{\"\(id)\":\"\(token)\",\"00000000-0000-4000-8000-000000000002\":\"\(token)\"}"))
  }
}
