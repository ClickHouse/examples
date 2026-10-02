import Vapor

func digest(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).hex }
func newInvitationSecret() -> String {
  let key = SymmetricKey(size: .bits256)
  let bytes = key.withUnsafeBytes { Data($0) }
  return bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-")
    .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}
func matchingDigest(_ left: String, _ right: String) -> Bool {
  let a = Array(left.utf8)
  let b = Array(right.utf8)
  guard a.count == 64, b.count == 64 else { return false }
  var difference: UInt8 = 0
  for index in 0..<64 { difference |= a[index] ^ b[index] }
  return difference == 0
}
