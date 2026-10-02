package experimentlog

import cats.effect.{IO, Resource}
import com.zaxxer.hikari.HikariConfig
import org.typelevel.doobie.hikari.HikariTransactor
import java.nio.file.{Files, Path}

object Database {
  def resource: Resource[IO, HikariTransactor[IO]] =
    Resource
      .eval(IO {
        def required(key: String) =
          sys.env.getOrElse(key, throw new IllegalArgumentException(s"$key is required"))
        val ca = required("PGSSLROOTCERT")
        require(Files.isRegularFile(Path.of(ca)), "Cloud CA file is required")
        val host = required("PGHOST")
        require(host.matches("[A-Za-z0-9.-]+"), "Invalid database hostname")
        val database = sys.env.getOrElse("PGDATABASE", "postgres")
        require(database.matches("[A-Za-z0-9_]+"), "Invalid database name")
        val port = sys.env.getOrElse("PGPORT", "5432").toInt
        require(port >= 1 && port <= 65535, "Invalid database port")
        val config = new HikariConfig()
        config.setDriverClassName("org.postgresql.Driver")
        config.setJdbcUrl(s"jdbc:postgresql://$host:$port/$database")
        config.setUsername(required("PGUSER"))
        config.setPassword(required("PGPASSWORD"))
        config.setMaximumPoolSize(4)
        config.setMinimumIdle(0)
        config.setConnectionTimeout(5000)
        config.setValidationTimeout(2000)
        config.setInitializationFailTimeout(10000)
        config.setTransactionIsolation("TRANSACTION_READ_COMMITTED")
        config.addDataSourceProperty("sslmode", "verify-full")
        config.addDataSourceProperty("sslrootcert", ca)
        config.addDataSourceProperty("connectTimeout", "10")
        config.addDataSourceProperty("socketTimeout", "15")
        config.addDataSourceProperty("ApplicationName", "experiment-log")
        config.addDataSourceProperty(
          "options",
          "-csearch_path=experiment_log,public -cstatement_timeout=10000 -clock_timeout=8000"
        )
        config
      })
      .flatMap(config => HikariTransactor.fromHikariConfig[IO](config, logHandler = None))
}
