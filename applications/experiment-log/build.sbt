ThisBuild / scalaVersion := "3.9.0"
ThisBuild / organization := "examples.clickhouse"
ThisBuild / version := "0.1.0"

val http4sVersion = "0.23.38"
val doobieVersion = "1.0.0-RC13" // Maintained published release candidate, not stable 1.0.

libraryDependencies ++= Seq(
  "org.http4s" %% "http4s-ember-server" % http4sVersion,
  "org.http4s" %% "http4s-dsl" % http4sVersion,
  "org.http4s" %% "http4s-circe" % http4sVersion,
  "org.typelevel" %% "cats-effect" % "3.7.1",
  "org.typelevel" %% "doobie-core" % doobieVersion,
  "org.typelevel" %% "doobie-hikari" % doobieVersion,
  "org.typelevel" %% "doobie-postgres" % doobieVersion,
  "org.typelevel" %% "doobie-postgres-circe" % doobieVersion,
  "io.circe" %% "circe-core" % "0.14.16",
  "io.circe" %% "circe-parser" % "0.14.16",
  "com.zaxxer" % "HikariCP" % "7.1.0",
  "org.postgresql" % "postgresql" % "42.7.13",
  "org.slf4j" % "slf4j-simple" % "2.0.17",
  "org.scalameta" %% "munit" % "1.3.6" % Test
)

// Record selected modules from the actual resolver, including test dependencies.
val resolvedModules = taskKey[String]("Canonical selected dependency record")
resolvedModules := (Compile / update).value.configurations.flatMap(_.modules)
  .filterNot(_.evicted).map(m => s"${m.module.organization}:${m.module.name}:${m.module.revision}")
  .distinct.sorted.mkString("", "\n", "\n")
val writeDependencyLock = taskKey[Unit]("Write resolved dependency record intentionally")
writeDependencyLock := IO.write(baseDirectory.value / "dependency-lock.txt", resolvedModules.value)
val verifyDependencyLock = taskKey[Unit]("Fail when resolved dependencies differ from committed record")
verifyDependencyLock := {
  val path = baseDirectory.value / "dependency-lock.txt"
  require(path.exists && IO.read(path) == resolvedModules.value, "Dependency record differs; review before writeDependencyLock")
}
val writeRuntimeClasspath = taskKey[Unit]("Write native production JVM classpath")
writeRuntimeClasspath := IO.write(baseDirectory.value / ".local/runtime-classpath.txt", (Runtime / fullClasspath).value.files.mkString(java.io.File.pathSeparator))

val writeTestClasspath = taskKey[Unit]("Write native live-check JVM classpath")
writeTestClasspath := IO.write(baseDirectory.value / ".local/test-classpath.txt", (Test / fullClasspath).value.files.mkString(java.io.File.pathSeparator))
