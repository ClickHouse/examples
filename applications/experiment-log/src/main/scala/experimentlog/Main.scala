package experimentlog

import cats.effect.{IO, IOApp}
import cats.syntax.all.*
import com.comcast.ip4s.*
import org.http4s.*
import org.http4s.circe.*
import org.http4s.dsl.io.*
import org.http4s.ember.server.EmberServerBuilder
import org.http4s.server.middleware.Timeout
import org.typelevel.doobie.implicits.*
import org.typelevel.doobie.*
import org.typelevel.doobie.postgres.implicits.*
import org.typelevel.doobie.Transactor
import io.circe.Json
import java.security.MessageDigest
import java.nio.charset.StandardCharsets
import java.util.UUID
import scala.concurrent.duration.*

object Auth {
  val projectA = UUID.fromString("00000000-0000-4000-8000-000000000001")
  val projectB = UUID.fromString("00000000-0000-4000-8000-000000000002")
  def configured: Vector[(Array[Byte], UUID)] = {
    val values = Vector("PROJECT_A_TOKEN" -> projectA, "PROJECT_B_TOKEN" -> projectB).map {
      case (key, id) =>
        val token = sys.env.getOrElse(key, throw new IllegalArgumentException(s"$key is required"))
        require(
          token.matches("[A-Za-z0-9_-]{32,128}"),
          "Tokens must be distinct URL-safe strings of 32–128 characters"
        )
        (token.getBytes(StandardCharsets.US_ASCII), id)
    }
    require(!MessageDigest.isEqual(values(0)._1, values(1)._1), "Project tokens must differ")
    values
  }
  def project(request: Request[IO], tokens: Vector[(Array[Byte], UUID)]): Option[UUID] = {
    val headers = request.headers.headers.filter(_.name.toString.equalsIgnoreCase("Authorization"))
    if (headers.size != 1) None
    else {
      val value = headers.head.value
      if (!value.startsWith("Bearer ") || value.length > 135) None
      else {
        val bytes = value.drop(7).getBytes(StandardCharsets.UTF_8)
        tokens.find { case (expected, _) => MessageDigest.isEqual(bytes, expected) }.map(_._2)
      }
    }
  }
}

object Main extends IOApp.Simple {
  def routes(xa: Transactor[IO], tokens: Vector[(Array[Byte], UUID)]): HttpRoutes[IO] = {
    def body(request: Request[IO]): IO[Json] = request.body
      .take(Domain.MaxBody.toLong + 1)
      .compile
      .to(Array)
      .timeout(5.seconds)
      .flatMap(bytes => IO(Domain.parse(bytes)))
    def error(status: Int, message: String) = IO.pure(
      Response[IO](Status.fromInt(status).toOption.get)
        .withEntity(Json.obj("error" -> Json.fromString(message)))
    )
    def protect(request: Request[IO])(operation: UUID => IO[Response[IO]]): IO[Response[IO]] =
      Auth.project(request, tokens) match {
        case None          => error(401, "A configured project bearer token is required.")
        case Some(project) =>
          operation(project).handleErrorWith {
            case failure: Rejection                       => error(failure.status, failure.message)
            case _: java.util.concurrent.TimeoutException => error(408, "Request timed out.")
            case _: java.sql.SQLException                 =>
              error(503, "The experiment log could not complete this request. Try again shortly.")
            case _ => error(500, "The request could not be completed.")
          }
      }
    HttpRoutes.of[IO] {
      case request @ GET -> Root / "project" =>
        protect(request)(project => Ok(Json.obj("id" -> Json.fromString(project.toString))))
      case request @ POST -> Root / "runs" =>
        protect(request) { project =>
          for {
            raw <- body(request)
            fields <- IO(Domain.run(raw))
            result <- Store.register(project, fields).transact(xa)
            response <- if (result._2) Created(result._1.json) else Ok(result._1.json)
          } yield response
        }
      case request @ GET -> Root / "runs" / id =>
        protect(request) { project =>
          IO(Domain.uuid(id))
            .flatMap(runId => Store.read(project, runId).transact(xa))
            .flatMap(saved => Ok(saved.json))
        }
      case request @ POST -> Root / "runs" / "search" =>
        protect(request) { project =>
          for {
            raw <- body(request)
            fields <- IO(Domain.search(raw))
            result <- Store.search(project, fields).transact(xa)
            response <- Ok(result)
          } yield response
        }
    }
  }

  def run: IO[Unit] = IO(Auth.configured).flatMap { tokens =>
    Database.resource.use { xa =>
      val api = Timeout(30.seconds)(routes(xa, tokens).orNotFound)
      val check = sql"SELECT id FROM experiment_log.projects"
        .query[UUID]
        .to[Vector]
        .transact(xa)
        .flatMap(ids =>
          IO.raiseUnless(ids.toSet == Set(Auth.projectA, Auth.projectB))(
            new IllegalStateException(
              "Seeded projects do not match the configured token identities"
            )
          )
        )
      check *> EmberServerBuilder
        .default[IO]
        .withHost(host"127.0.0.1")
        .withPort(port"8080")
        .withIdleTimeout(35.seconds)
        .withRequestHeaderReceiveTimeout(5.seconds)
        .withHttpApp(api)
        .build
        .useForever
    }
  }
}
