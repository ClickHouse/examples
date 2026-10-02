package experimentlog

import java.nio.charset.{CodingErrorAction, StandardCharsets}
import java.time.Instant
import java.util.{Base64, UUID}
import io.circe.{Json, JsonObject}
import io.circe.jawn.JawnParser
import scala.util.Try

final case class Rejection(message: String, status: Int = 422) extends RuntimeException(message)
final case class Measurement(name: String, value: BigDecimal)
final case class RunInput(
    requestId: UUID,
    title: String,
    config: Json,
    measurements: Vector[Measurement]
) {
  val semantic: Json = Json.obj(
    "title" -> Json.fromString(title),
    "config" -> config,
    "measurements" -> Json.fromFields(
      measurements.sortBy(_.name).map(m => m.name -> Json.fromString(Domain.decimalText(m.value)))
    )
  )
}
final case class Cursor(createdAt: Instant, id: UUID) {
  def encoded: String = Base64.getUrlEncoder.withoutPadding.encodeToString(
    (createdAt.toString + "|" + id.toString).getBytes(StandardCharsets.US_ASCII)
  )
}
final case class Search(config: Json, title: String, limit: Int, cursor: Option[Cursor])

object Domain {
  val MaxBody = 16384
  private val parser = new JawnParser(maxValueSize = Some(MaxBody), allowDuplicateKeys = false)
  private val keyPattern = "[A-Za-z][A-Za-z0-9_]{0,23}".r
  private val namePattern = "[a-z][a-z0-9_]{0,31}".r
  private val decimalPattern = "-?(0|[1-9][0-9]{0,6})(\\.[0-9]{1,6})?".r
  private val numberPattern = "-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?".r

  def ensure(condition: Boolean, message: String): Unit = if (!condition) throw Rejection(message)
  def decimalText(value: BigDecimal): String = value.bigDecimal.stripTrailingZeros.toPlainString

  def safeText(value: String, max: Int): String = {
    ensure(value.codePointCount(0, value.length) <= max, "Text exceeds its character bound.")
    var i = 0
    while (i < value.length) {
      val c = value.charAt(i)
      if (Character.isHighSurrogate(c)) {
        ensure(
          i + 1 < value.length && Character.isLowSurrogate(value.charAt(i + 1)),
          "Invalid Unicode."
        )
        i += 2
      } else {
        ensure(
          !Character.isLowSurrogate(c) && !Character.isISOControl(c),
          "Controls or invalid Unicode are not allowed."
        )
        i += 1
      }
    }
    value
  }

  // Bound nesting and numeric lexemes before Circe/BigDecimal can expand an exponent.
  private def lexicalBounds(raw: String): Unit = {
    var i = 0
    var depth = 0
    var quoted = false
    var escaped = false
    while (i < raw.length) {
      val c = raw.charAt(i)
      if (quoted) {
        if (escaped) escaped = false
        else if (c == '\\') escaped = true
        else if (c == '"') quoted = false
      } else if (c == '"') quoted = true
      else if (c == '{' || c == '[') {
        depth += 1
        ensure(depth <= 4, "JSON nesting exceeds the envelope bound.")
      } else if (c == '}' || c == ']') depth -= 1
      else if (c == '-' || c.isDigit) {
        val start = i
        while (i < raw.length && "0123456789.eE+-".contains(raw.charAt(i))) i += 1
        val token = raw.substring(start, i)
        ensure(
          token.length <= 40 && numberPattern.matches(token),
          "Invalid or oversized numeric literal."
        )
        val exponent = token.indexWhere(ch => ch == 'e' || ch == 'E')
        if (exponent >= 0) {
          val suffix = token.substring(exponent + 1)
          ensure(
            suffix.length <= 3 && Try(suffix.toInt).toOption.exists(n => math.abs(n) <= 12),
            "Numeric exponent is out of bounds."
          )
        }
        i -= 1
      }
      i += 1
    }
  }

  def parse(bytes: Array[Byte]): Json = {
    ensure(bytes.length <= MaxBody, "Request exceeds 16 KiB.")
    val decoder = StandardCharsets.UTF_8.newDecoder
      .onMalformedInput(CodingErrorAction.REPORT)
      .onUnmappableCharacter(CodingErrorAction.REPORT)
    val raw = Try(decoder.decode(java.nio.ByteBuffer.wrap(bytes)).toString)
      .getOrElse(throw Rejection("Request must be valid UTF-8.", 400))
    lexicalBounds(raw)
    parser.parse(raw).getOrElse(throw Rejection("Malformed JSON or duplicate object keys.", 400))
  }

  private def obj(json: Json, allowed: Set[String]): JsonObject = {
    val fields = json.asObject.getOrElse(throw Rejection("An object is required."))
    ensure(fields.keys.forall(allowed), "Unknown field.")
    fields
  }
  private def string(fields: JsonObject, key: String): String =
    fields(key).flatMap(_.asString).getOrElse(throw Rejection(s"$key must be a string."))
  def uuid(value: String): UUID = {
    ensure(
      value.matches("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"),
      "A canonical UUID shape is required."
    )
    UUID.fromString(value)
  }
  def config(json: Json): Json = {
    val fields = json.asObject.getOrElse(throw Rejection("Configuration must be an object."))
    ensure(fields.size <= 10, "Configuration permits at most 10 keys.")
    Json.fromFields(fields.toVector.sortBy(_._1).map { case (key, value) =>
      ensure(keyPattern.matches(key), "Configuration key must match [A-Za-z][A-Za-z0-9_]{0,23}.")
      val normalized = value.asString match {
        case Some(text)              => Json.fromString(safeText(text, 120))
        case None if value.isBoolean => value
        case None if value.isNumber  =>
          val decimal = value.asNumber
            .flatMap(_.toBigDecimal)
            .getOrElse(throw Rejection("Invalid decimal configuration value."))
          val stripped = decimal.bigDecimal.stripTrailingZeros
          ensure(
            decimal.abs <= BigDecimal(1000000) && math
              .max(0, stripped.scale) <= 6 && stripped.precision <= 13,
            "Configuration decimal exceeds exact range/scale."
          )
          Json.fromBigDecimal(BigDecimal(stripped))
        case _ =>
          throw Rejection(
            "Configuration values must be scalar string, boolean or number; null is not allowed."
          )
      }
      key -> normalized
    })
  }
  def run(json: Json): RunInput = {
    val fields = obj(json, Set("requestId", "title", "config", "measurements"))
    val request = uuid(string(fields, "requestId"))
    val title = safeText(string(fields, "title"), 120).trim
    ensure(title.nonEmpty, "Title is required.")
    val settings = config(fields("config").getOrElse(throw Rejection("config is required.")))
    val rows = fields("measurements")
      .flatMap(_.asArray)
      .getOrElse(throw Rejection("measurements must be an array."))
    ensure(rows.nonEmpty && rows.size <= 10, "Supply 1–10 measurements.")
    val measurements = rows.map { json =>
      val values = obj(json, Set("name", "value"))
      val name = string(values, "name")
      ensure(namePattern.matches(name), "Measurement name must match [a-z][a-z0-9_]{0,31}.")
      val raw = string(values, "value")
      ensure(
        raw.length <= 16 && decimalPattern.matches(raw),
        "Measurement value must be a plain decimal string with at most 6 fractional digits."
      )
      val decimal = BigDecimal(raw)
      ensure(decimal.abs <= BigDecimal(1000000), "Measurement magnitude exceeds 1,000,000.")
      Measurement(name, BigDecimal(decimal.bigDecimal.stripTrailingZeros))
    }
    ensure(
      measurements.map(_.name).distinct.size == measurements.size,
      "Measurement names must be unique."
    )
    RunInput(request, title, settings, measurements.sortBy(_.name))
  }
  def cursor(value: String): Cursor = {
    ensure(value.length <= 120 && value.matches("[A-Za-z0-9_-]+"), "Invalid cursor.")
    val raw = Try(new String(Base64.getUrlDecoder.decode(value), StandardCharsets.US_ASCII))
      .getOrElse(throw Rejection("Invalid cursor."))
    val parts = raw.split("\\|", -1)
    ensure(parts.length == 2, "Invalid cursor.")
    val at = Try(Instant.parse(parts(0))).getOrElse(throw Rejection("Invalid cursor timestamp."))
    ensure(
      at.isAfter(Instant.parse("1970-01-01T00:00:00Z")) && at.isBefore(
        Instant.parse("2100-01-01T00:00:00Z")
      ),
      "Cursor timestamp out of bounds."
    )
    val result = Cursor(at, uuid(parts(1)))
    ensure(result.encoded == value, "Noncanonical cursor.")
    result
  }
  def search(json: Json): Search = {
    val fields = obj(json, Set("config", "title", "limit", "cursor"))
    val settings = config(fields("config").getOrElse(Json.obj()))
    val title = fields("title").map(_ => safeText(string(fields, "title"), 80)).getOrElse("")
    val limit = fields("limit")
      .map(_.asNumber.flatMap(_.toInt).getOrElse(throw Rejection("limit must be an integer.")))
      .getOrElse(10)
    ensure(limit >= 1 && limit <= 20, "limit must be 1–20.")
    val after = fields("cursor").map(_ => cursor(string(fields, "cursor")))
    Search(settings, title, limit, after)
  }
}
