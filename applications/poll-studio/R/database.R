required_env <- function(name) {
  value <- Sys.getenv(name, unset = "")
  if (!nzchar(value)) stop(paste("Missing configuration:", name), call. = FALSE)
  value
}

connection_options <- function() {
  list(drv = RPostgres::Postgres(), host = required_env("PGHOST"),
       port = required_env("PGPORT"), dbname = required_env("PGDATABASE"),
       user = required_env("PGUSER"), password = required_env("PGPASSWORD"),
       sslmode = "verify-full", sslrootcert = required_env("PGSSLROOTCERT"),
       connect_timeout = "10", bigint = "character", timezone = "UTC",
       application_name = "poll-studio",
       options = "-c statement_timeout=5000 -c lock_timeout=3000 -c idle_in_transaction_session_timeout=5000")
}

new_pool <- function() {
  do.call(pool::dbPool, c(connection_options(), list(minSize = 1L, maxSize = 4L)))
}
