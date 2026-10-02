package experimentlog

import cats.syntax.all.*
import org.typelevel.doobie.*
import org.typelevel.doobie.implicits.*
import org.typelevel.doobie.postgres.implicits.*
import org.typelevel.doobie.postgres.circe.jsonb.implicits.*
import io.circe.Json
import java.time.Instant
import java.util.UUID

final case class RunRow(id: UUID, requestId: UUID, title: String, config: Json, createdAt: Instant)
final case class Saved(row: RunRow, measurements: Vector[Measurement]) {
  def json: Json = Json.obj(
    "id" -> Json.fromString(row.id.toString),
    "requestId" -> Json.fromString(row.requestId.toString),
    "title" -> Json.fromString(row.title),
    "config" -> row.config,
    "createdAt" -> Json.fromString(row.createdAt.toString),
    "measurements" -> Json.fromValues(
      measurements.map(m =>
        Json.obj(
          "name" -> Json.fromString(m.name),
          "value" -> Json.fromString(Domain.decimalText(m.value))
        )
      )
    )
  )
}

object Store {
  def header(project: UUID, id: UUID): Query0[RunRow] =
    sql"""SELECT id,request_id,title,config,created_at FROM experiment_log.runs
      WHERE project_id=$project AND id=$id""".query[RunRow]

  def read(project: UUID, id: UUID): ConnectionIO[Saved] = for {
    row <- header(project, id).option.flatMap(
      _.liftTo[ConnectionIO](Rejection("Run not found.", 404))
    )
    measurements <- sql"""SELECT name,value FROM experiment_log.measurements
      WHERE project_id=$project AND run_id=$id ORDER BY name""".query[Measurement].to[Vector]
  } yield Saved(row, measurements)

  def claim(project: UUID, input: RunInput, id: UUID): Query0[UUID] = {
    val title = input.title
    val config = input.config
    val payload = input.semantic
    val request = input.requestId
    sql"""INSERT INTO experiment_log.runs(id,project_id,request_id,title,config,request_payload)
      VALUES($id,$project,$request,$title,$config,$payload)
      ON CONFLICT(project_id,request_id) DO NOTHING RETURNING id""".query[UUID]
  }

  val measurementInsert = Update[(UUID, UUID, String, BigDecimal)](
    "INSERT INTO experiment_log.measurements(project_id,run_id,name,value) VALUES(?,?,?,?)"
  )
  def measurements(project: UUID, id: UUID): Query0[Measurement] =
    sql"""SELECT name,value FROM experiment_log.measurements
      WHERE project_id=$project AND run_id=$id ORDER BY name""".query[Measurement]

  def register(project: UUID, input: RunInput): ConnectionIO[(Saved, Boolean)] = {
    val id = UUID.randomUUID()
    val payload = input.semantic
    val request = input.requestId
    for {
      // One ConnectionIO, interpreted by one transact at the HTTP boundary.
      claimed <- claim(project, input, id).option
      result <- claimed match {
        case Some(inserted) =>
          val rows = input.measurements.map(m => (project, inserted, m.name, m.value))
          for {
            _ <- measurementInsert.updateMany(rows)
            saved <- read(project, inserted)
          } yield (saved, true)
        case None =>
          // A fresh READ COMMITTED statement sees the concurrent winner after conflict wait.
          for {
            existing <- sql"""SELECT id,request_payload=$payload FROM experiment_log.runs
              WHERE project_id=$project AND request_id=$request""".query[(UUID, Boolean)].unique
            _ <-
              if (existing._2) ().pure[ConnectionIO]
              else
                Rejection("This request UUID already records a different run.", 409)
                  .raiseError[ConnectionIO, Unit]
            saved <- read(project, existing._1)
          } yield (saved, false)
      }
    } yield result
  }

  def searchHeaders(project: UUID, search: Search): Query0[RunRow] = {
    val pattern =
      "%" + search.title.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"
    val filter = search.config
    val bound = search.limit.toLong + 1
    val base = fr"""SELECT id,request_id,title,config,created_at FROM experiment_log.runs
      WHERE project_id=$project AND config @> $filter AND title ILIKE $pattern ESCAPE E'\\' """
    val after =
      search.cursor.fold(Fragment.empty)(c => fr" AND (created_at,id) < (${c.createdAt},${c.id}) ")
    (base ++ after ++ fr"ORDER BY created_at DESC,id DESC LIMIT $bound").query[RunRow]
  }

  def measurementsFor(project: UUID, ids: Vector[UUID]): Query0[(UUID, String, BigDecimal)] = {
    val bound = ids.toArray
    sql"""SELECT run_id,name,value FROM experiment_log.measurements
      WHERE project_id=$project AND run_id=ANY($bound) ORDER BY run_id,name"""
      .query[(UUID, String, BigDecimal)]
  }

  def search(project: UUID, input: Search): ConnectionIO[Json] = for {
    rows <- searchHeaders(project, input).to[Vector]
    selected = rows.take(input.limit)
    children <-
      if (selected.isEmpty) Vector.empty[(UUID, String, BigDecimal)].pure[ConnectionIO]
      else measurementsFor(project, selected.map(_.id)).to[Vector]
    grouped = children.groupMap(_._1)(row => Measurement(row._2, row._3))
    saved = selected.map(row => Saved(row, grouped.getOrElse(row.id, Vector.empty)))
    next =
      if (rows.size > input.limit)
        selected.lastOption.map(row => Cursor(row.createdAt, row.id).encoded)
      else None
  } yield Json.obj(
    "runs" -> Json.fromValues(saved.map(_.json)),
    "nextCursor" -> next.fold(Json.Null)(Json.fromString)
  )
}
