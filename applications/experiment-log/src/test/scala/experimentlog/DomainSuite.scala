package experimentlog

import io.circe.Json
import java.nio.charset.StandardCharsets
import java.time.Instant
import java.util.UUID

class DomainSuite extends munit.FunSuite {
  val request = "00000000-0000-4000-8000-000000000010"
  def parse(value: String) = Domain.parse(value.getBytes(StandardCharsets.UTF_8))
  def payload(value: String) =
    s"""{"requestId":"$request","title":"Synthetic run","config":{"optimizer":"adam","rate":0.000001},"measurements":[{"name":"accuracy","value":"$value"}]}"""

  test("exact decimal values never pass through Double or rounding") {
    val saved = Domain.run(parse(payload("0.123456")))
    assertEquals(Domain.decimalText(saved.measurements.head.value), "0.123456")
    for (bad <- Vector("0.1234567", "1000000.000001", "1e-6", "NaN", "01.2", "9" * 5000))
      intercept[Rejection](Domain.run(parse(payload(bad))))
  }
  test("semantic equality ignores object and measurement ordering and decimal trailing zeros") {
    val first = Domain.run(parse(payload("1.000000")))
    val other = Domain.run(
      parse(
        s"""{"measurements":[{"value":"1.0","name":"accuracy"}],"config":{"rate":0.000001,"optimizer":"adam"},"title":"Synthetic run","requestId":"$request"}"""
      )
    )
    assertEquals(first.semantic, other.semantic)
    assertNotEquals(first.semantic, other.copy(title = "Different").semantic)
  }
  test("numeric lexeme exponent and nesting bounds precede decimal expansion") {
    for (bad <- Vector("1e999999999", "1e13", "9" * 100))
      intercept[Rejection](parse(s"""{"config":{"number":$bad}}"""))
    intercept[Rejection](parse("[[[[[0]]]]]"))
    intercept[Rejection](Domain.config(parse("""{"nested":{"key":1}}""")))
    intercept[Rejection](Domain.config(parse("""{"nothing":null}""")))
    intercept[Rejection](Domain.config(parse("""{"number":0.0000001}""")))
  }
  test("duplicate keys malformed UTF-8 and unpaired surrogates fail safely") {
    intercept[Rejection](parse("""{"value":1,"value":2}"""))
    intercept[Rejection](Domain.parse(Array(0xc3.toByte, 0x28.toByte)))
    intercept[Rejection](Domain.config(parse("""{"text":"\ud800"}""")))
    intercept[Rejection](Domain.safeText("Bad\u0085", 120))
    assertEquals(Domain.safeText("Idea 😀", 120), "Idea 😀")
  }
  test("measurement names are unique and caller cannot select project") {
    intercept[Rejection](
      Domain.run(parse(payload("1").replace("}]}", """},{"name":"accuracy","value":"2"}]}""")))
    )
    intercept[Rejection](
      Domain.run(parse(payload("1").dropRight(1) + """, "projectId":"other"}"""))
    )
  }
  test("cursor is bounded canonical and preserves full timestamp and UUID") {
    val cursor = Cursor(Instant.parse("2026-10-02T12:00:00.123456Z"), UUID.fromString(request))
    assertEquals(Domain.cursor(cursor.encoded), cursor)
    for (bad <- Vector("!invalid", "x" * 1000, cursor.encoded + "="))
      intercept[Rejection](Domain.cursor(bad))
    intercept[Rejection](Domain.search(parse("""{"limit":21}""")))
  }
}
