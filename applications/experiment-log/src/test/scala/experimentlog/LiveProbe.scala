package experimentlog

import cats.effect.{IO, IOApp}
import cats.syntax.all.*
import org.typelevel.doobie.implicits.*
import org.typelevel.doobie.postgres.implicits.*
import org.typelevel.doobie.postgres.circe.jsonb.implicits.*
import io.circe.Json
import java.sql.{Connection, DriverManager}
import java.lang.reflect.{InvocationTargetException, Proxy}
import java.util.concurrent.atomic.AtomicInteger
import org.typelevel.doobie.Transactor
import java.util.{Properties, UUID}
import java.time.Instant
import javax.net.ssl.{HostnameVerifier, SSLSession}
import org.postgresql.ssl.PGjdbcHostnameVerifier

// Test-only verifier: retain the actual TLS session/CA validation, substitute
// a wrong hostname for pgJDBC's native hostname verification control.
class WrongHostnameVerifier extends HostnameVerifier {
  override def verify(hostname: String, session: SSLSession): Boolean =
    PGjdbcHostnameVerifier.INSTANCE.verify("wrong-hostname.invalid", session)
}

object LiveProbe extends IOApp.Simple {
  def connect(overrides: Map[String, String]): Connection = {
    val properties = new Properties()
    Map(
      "user" -> sys.env("PGUSER"),
      "password" -> sys.env("PGPASSWORD"),
      "sslmode" -> "verify-full",
      "sslrootcert" -> sys.env("PGSSLROOTCERT"),
      "connectTimeout" -> "10",
      "socketTimeout" -> "15"
    ).foreach { case (key, value) => properties.setProperty(key, value) }
    overrides.foreach { case (key, value) => properties.setProperty(key, value) }
    DriverManager.getConnection(
      s"jdbc:postgresql://${sys.env("PGHOST")}:${sys.env.getOrElse("PGPORT", "5432")}/${sys.env.getOrElse("PGDATABASE", "postgres")}",
      properties
    )
  }
  def driverControl(overrides: Map[String, String]): Unit = {
    val connection = connect(overrides)
    try {
      val statement = connection.createStatement()
      try {
        val result = statement.executeQuery("SELECT 1")
        try { require(result.next() && result.getInt(1) == 1) }
        finally result.close()
      } finally statement.close()
    } finally connection.close()
  }
  def messages(error: Throwable): String = Iterator
    .iterate(Option(error))(_.flatMap(e => Option(e.getCause)))
    .takeWhile(_.nonEmpty)
    .flatMap(_.map(_.getMessage))
    .mkString(" | ")

  def run: IO[Unit] = for {
    _ <- IO.blocking(driverControl(Map.empty))
    _ <- IO.println("pgJDBC verify-full positive connection passed")
    wrongCa <- IO
      .blocking(driverControl(Map("sslrootcert" -> "/etc/ssl/certs/ca-certificates.crt")))
      .attempt
    _ <- IO {
      require(wrongCa.isLeft, "wrong CA must fail");
      require(
        messages(wrongCa.swap.toOption.get).toLowerCase
          .matches("(?s).*(certificate|pkix|trust anchor|certification path).*"),
        "CA control must fail for certificate validation"
      )
    }
    _ <- IO.println("pgJDBC wrong CA reached a certificate-specific failure")
    wrongName <- IO
      .blocking(driverControl(Map("sslhostnameverifier" -> classOf[WrongHostnameVerifier].getName)))
      .attempt
    _ <- IO {
      require(wrongName.isLeft, "wrong hostname must fail");
      require(
        messages(wrongName.swap.toOption.get).toLowerCase.matches("(?s).*(hostname|host name).*"),
        "hostname control must fail during certificate name validation"
      )
    }
    _ <- IO.println(
      "pgJDBC actual TLS session + native verifier substituted-hostname negative passed; production verifier unchanged"
    )
    _ <- IO
      .blocking(connect(Map.empty))
      .bracket { connection =>
        val count = new AtomicInteger(0)
        val wrapped = Proxy
          .newProxyInstance(
            classOf[Connection].getClassLoader,
            Array(classOf[Connection]),
            (_, method, arguments) => {
              if (method.getName == "prepareStatement") count.incrementAndGet()
              try method.invoke(connection, Option(arguments).getOrElse(Array.empty[AnyRef])*)
              catch { case error: InvocationTargetException => throw error.getCause }
            }
          )
          .asInstanceOf[Connection]
        val xa = Transactor.fromConnection[IO](wrapped, logHandler = None)
        Store
          .search(Auth.projectA, Search(Json.obj(), "", 20, None))
          .transact(xa)
          .flatMap(result =>
            IO {
              require(
                result.hcursor.downField("runs").focus.flatMap(_.asArray).exists(_.nonEmpty),
                "count control requires persisted fixture rows"
              )
              require(
                count.get == 2,
                s"Expected exactly two prepared search statements, got ${count.get}"
              )
              println(
                "Observed exactly 2 JDBC prepared statements for populated limit-20 search; no SQL parameter logging"
              )
            }
          )
      }(connection => IO.blocking(connection.close()))
    _ <- Database.resource.use { xa =>
      val project = Auth.projectA
      val id = UUID.randomUUID()
      val input = RunInput(
        UUID.randomUUID(),
        "Typecheck fixture",
        Json.obj("optimizer" -> Json.fromString("adam")),
        Vector(Measurement("accuracy", BigDecimal("0.123456")))
      )
      val checks = Vector(
        "read header" -> Store.header(project, id).analysis,
        "measurement decimal" -> Store.measurements(project, id).analysis,
        "bounded measurement batch" -> Store.measurementsFor(project, Vector(id)).analysis,
        "retained insert returning" -> Store.claim(project, input, id).analysis,
        "child insert exact numeric" -> Store.measurementInsert
          .toUpdate0((project, id, "accuracy", BigDecimal("0.123456")))
          .analysis,
        "containment search" -> Store
          .searchHeaders(project, Search(input.config, "%_", 5, None))
          .analysis,
        "cursor search" -> Store
          .searchHeaders(
            project,
            Search(
              input.config,
              "",
              5,
              Some(Cursor(Instant.parse("2026-10-02T12:00:00.123456Z"), id))
            )
          )
          .analysis
      )
      for {
        _ <- checks.traverse_ { case (name, check) =>
          check
            .transact(xa)
            .flatMap(a =>
              IO {
                require(
                  a.alignmentErrors.isEmpty,
                  s"$name SQL type mismatch: ${a.alignmentErrors}"
                );
                println(s"doobie live analysis passed: $name")
              }
            )
        }
        version <- sql"SELECT version()".query[String].unique.transact(xa)
        _ <- IO.println(version)
        definition <-
          sql"SELECT indexdef FROM pg_indexes WHERE schemaname='experiment_log' AND indexname='runs_config_gin'"
            .query[String]
            .unique
            .transact(xa)
        _ <- IO.println(definition)
        filter = input.config
        plan <-
          sql"EXPLAIN SELECT id FROM experiment_log.runs WHERE project_id=$project AND config @> $filter"
            .query[String]
            .to[Vector]
            .transact(xa)
        _ <- IO.println(
          "Actual small-fixture EXPLAIN (planner not forced):\n" + plan.mkString("\n")
        )
      } yield ()
    }
  } yield ()
}
