# Targeted Cloud tie-order regression. Use a freshly migrated dedicated fixture, no seed.
source("R/validation.R")
source("R/database.R")
source("R/polls.R")

opts <- connection_options()
owner_opts <- opts
owner_opts$user <- "polls_migration"
owner_opts$password <- required_env("MIGRATION_PASSWORD")
owner <- do.call(DBI::dbConnect, owner_opts)
db <- new_pool()
tryCatch({
  stopifnot(DBI::dbGetQuery(owner, "SELECT count(*)::integer AS n FROM poll_studio.polls")$n == 0L)
  DBI::dbExecute(owner,
    "INSERT INTO poll_studio.polls(question, created_at)
     SELECT 'Tied fixture ' || n, '2026-10-02 00:00:00+00'::timestamptz
     FROM generate_series(1, 12) AS g(n)")
  DBI::dbExecute(owner,
    "INSERT INTO poll_studio.choices(poll_id, position, label)
     SELECT p.id, c.position, c.label FROM poll_studio.polls p
     CROSS JOIN (VALUES(1, 'Blue'), (2, 'Orange')) AS c(position, label)")
  old <- DBI::dbGetQuery(owner,
    "SELECT id::text AS id FROM poll_studio.polls ORDER BY created_at DESC, id DESC")$id
  expected <- as.character(12:1)
  stopifnot(!identical(old, expected))
  rows <- list_polls(db)
  stopifnot(identical(rows$id, expected), nrow(rows) == 12L,
            length(unique(rows$id)) == 12L, length(unique(rows$created_at)) == 1L)
  cat("CLOUD ORDERING PASS: actual runtime pool returned", paste(rows$id, collapse = ","), "\n")
}, finally = {
  pool::poolClose(db)
  DBI::dbDisconnect(owner)
})
