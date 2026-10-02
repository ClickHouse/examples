source("R/validation.R")
source("R/database.R")
source("R/polls.R")
source("test/domain.R")

evidence <- required_env("EVIDENCE_DIR")
dir.create(evidence, recursive = TRUE, showWarnings = FALSE)
opts <- connection_options()
db <- new_pool()
owner_opts <- opts
owner_opts$user <- "polls_migration"
owner_opts$password <- required_env("MIGRATION_PASSWORD")
owner <- do.call(DBI::dbConnect, owner_opts)
admin_opts <- opts
admin_opts$user <- required_env("ADMIN_USER")
admin_opts$password <- required_env("ADMIN_PASSWORD")
admin_opts$options <- "-c statement_timeout=30000 -c lock_timeout=30000 -c idle_in_transaction_session_timeout=30000"
admin <- do.call(DBI::dbConnect, admin_opts)

cloud_check <- function(name, action) {
  action()
  cat("CLOUD PASS:", name, "\n")
}
choices_for <- function(id) poll_summary(db, id)$choice_id
make_poll <- function(label) create_poll(db, paste(label, format(Sys.time(), "%Y%m%d%H%M%OS6")), c("Garden", "Paper"))
assert_db_error <- function(action, pattern) {
  error <- tryCatch({ action(); NULL }, error = identity)
  stopifnot(inherits(error, "error"), grepl(pattern, conditionMessage(error), ignore.case = TRUE))
  invisible(error)
}
spawn_worker <- function(task, poll_id, choice_id = "1", code = "PLACEHOLDER", suffix) {
  output <- file.path(evidence, paste0(suffix, ".json"))
  unlink(output)
  system2(file.path(R.home("bin"), "Rscript"),
          args = vapply(c("test/worker.R", task, poll_id, choice_id, code, output), shQuote, character(1)),
          stdout = file.path(evidence, paste0(suffix, ".log")),
          stderr = file.path(evidence, paste0(suffix, ".log")), wait = FALSE)
  output
}
await_result <- function(path) {
  for (attempt in seq_len(200L)) {
    if (file.exists(path)) return(jsonlite::read_json(path, simplifyVector = TRUE))
    Sys.sleep(0.1)
  }
  stop("Independent R worker timed out")
}
wait_blocked <- function(number) {
  for (attempt in seq_len(100L)) {
    DBI::dbExecute(admin, "SELECT pg_stat_clear_snapshot()")
    rows <- DBI::dbGetQuery(admin,
      "SELECT count(*)::integer AS n FROM pg_stat_activity
       WHERE application_name = 'poll-studio' AND cardinality(pg_blocking_pids(pid)) > 0")
    if (rows$n[[1]] >= number) return(invisible(TRUE))
    Sys.sleep(0.1)
  }
  stop("Did not observe expected independent blocked database sessions")
}
lock_poll <- function(id) {
  DBI::dbBegin(admin)
  DBI::dbGetQuery(admin, "SELECT id FROM poll_studio.polls WHERE id = $1::bigint FOR UPDATE",
                  params = list(id))
}

tryCatch({
  cloud_check("positive verified connection, atomic creation and stored chart counts", function() {
    stopifnot(DBI::dbGetQuery(db, "SELECT current_user AS role")$role == "polls_app")
    id <- make_poll("Creation")
    choices <- choices_for(id)
    stopifnot(length(choices) == 2L)
    first <- record_response(db, id, choices[[1]], "sample_001")
    repeat_result <- record_response(db, id, choices[[1]], "SAMPLE_001")
    stopifnot(!first$replayed, repeat_result$replayed, identical(first$id, repeat_result$id))
    expect_error(function() record_response(db, id, choices[[2]], "SAMPLE_001"), "poll_conflict")
    close_poll(db, id)
    retained <- record_response(db, id, choices[[1]], "SAMPLE_001")
    stopifnot(retained$replayed, identical(first$id, retained$id))
    expect_error(function() record_response(db, id, choices[[1]], "NEW_CODE"), "poll_conflict")
    summary <- poll_summary(db, id)
    stopifnot(sum(summary$responses) == 1L, all(summary$response_count == 1L), all(summary$closed))
  })

  cloud_check("second-write creation and response failures roll back earlier changes", function() {
    DBI::dbExecute(owner,
      "CREATE FUNCTION poll_studio.reject_test_choice() RETURNS trigger LANGUAGE plpgsql AS $$
       BEGIN IF NEW.label = 'FORCE_REJECT_CHOICE' THEN RAISE EXCEPTION 'test choice rejection'; END IF;
       RETURN NEW; END $$")
    DBI::dbExecute(owner, "CREATE TRIGGER reject_test_choice BEFORE INSERT ON poll_studio.choices
                          FOR EACH ROW EXECUTE FUNCTION poll_studio.reject_test_choice()")
    question <- "Atomic rollback test fixture"
    assert_db_error(function() create_poll(db, question, c("Allowed first", "FORCE_REJECT_CHOICE")), "test choice rejection")
    stopifnot(DBI::dbGetQuery(db, "SELECT count(*)::integer AS n FROM poll_studio.polls WHERE question = $1",
                              params = list(question))$n == 0L)
    stopifnot(DBI::dbGetQuery(db, "SELECT count(*)::integer AS n FROM poll_studio.choices WHERE label = 'Allowed first'")$n == 0L)
    DBI::dbExecute(owner, "DROP TRIGGER reject_test_choice ON poll_studio.choices")
    DBI::dbExecute(owner, "DROP FUNCTION poll_studio.reject_test_choice()")
    id <- make_poll("Response rollback")
    choice <- choices_for(id)[[1]]
    DBI::dbExecute(owner,
      "CREATE FUNCTION poll_studio.reject_test_response() RETURNS trigger LANGUAGE plpgsql AS $$
       BEGIN IF NEW.participant_code = 'FAIL_RESPONSE' THEN RAISE EXCEPTION 'test response rejection'; END IF;
       RETURN NEW; END $$")
    DBI::dbExecute(owner, "CREATE TRIGGER reject_test_response BEFORE INSERT ON poll_studio.responses
                          FOR EACH ROW EXECUTE FUNCTION poll_studio.reject_test_response()")
    assert_db_error(function() record_response(db, id, choice, "FAIL_RESPONSE"), "test response rejection")
    stopifnot(all(poll_summary(db, id)$response_count == 0L), sum(poll_summary(db, id)$responses) == 0L)
    DBI::dbExecute(owner, "DROP TRIGGER reject_test_response ON poll_studio.responses")
    DBI::dbExecute(owner, "DROP FUNCTION poll_studio.reject_test_response()")
    record_response(db, id, choice, "FAIL_RESPONSE")
    stopifnot(sum(poll_summary(db, id)$responses) == 1L)
  })

  cloud_check("composite foreign key, natural-key uniqueness and actual role grants", function() {
    first <- make_poll("Foreign first")
    second <- make_poll("Foreign second")
    choice <- choices_for(second)[[1]]
    assert_db_error(function() DBI::dbExecute(db,
      "INSERT INTO poll_studio.responses (poll_id, choice_id, participant_code) VALUES ($1::bigint, $2::bigint, 'FOREIGN_TEST')",
      params = list(first, choice)), "response_poll_choice")
    choice <- choices_for(first)[[1]]
    record_response(db, first, choice, "UNIQUE_TEST")
    assert_db_error(function() DBI::dbExecute(db,
      "INSERT INTO poll_studio.responses (poll_id, choice_id, participant_code) VALUES ($1::bigint, $2::bigint, 'UNIQUE_TEST')",
      params = list(first, choice)), "response_poll_code")
    for (query in c("UPDATE poll_studio.responses SET participant_code = 'CHANGED'",
                    "DELETE FROM poll_studio.responses", "UPDATE poll_studio.choices SET label = 'CHANGED'",
                    "DELETE FROM poll_studio.choices", "UPDATE poll_studio.polls SET question = 'CHANGED'",
                    "DELETE FROM poll_studio.polls", "CREATE TABLE poll_studio.forbidden (id integer)",
                    "CREATE SCHEMA forbidden", "CREATE TEMP TABLE forbidden (id integer)",
                    "SELECT * FROM poll_studio.schema_migrations")) {
      assert_db_error(function() DBI::dbExecute(db, query), "permission denied")
    }
  })

  cloud_check("independent same-code workers serialize and retain one response", function() {
    id <- make_poll("Race repeat")
    choice <- choices_for(id)[[1]]
    lock_poll(id)
    a <- spawn_worker("respond", id, choice, "RACE_CODE", "same-a")
    b <- spawn_worker("respond", id, choice, "RACE_CODE", "same-b")
    wait_blocked(2L)
    DBI::dbCommit(admin)
    one <- await_result(a)
    two <- await_result(b)
    stopifnot(is.null(one$error), is.null(two$error), identical(one$id, two$id),
              xor(one$replayed, two$replayed), sum(poll_summary(db, id)$responses) == 1L,
              all(poll_summary(db, id)$response_count == 1L))
  })

  cloud_check("held parent lock proves close-first and response-first ordering", function() {
    id <- make_poll("Close first")
    choice <- choices_for(id)[[1]]
    lock_poll(id)
    waiting <- spawn_worker("respond", id, choice, "LATE_CODE", "close-first")
    wait_blocked(1L)
    DBI::dbExecute(admin, "UPDATE poll_studio.polls SET closed_at = clock_timestamp() WHERE id = $1::bigint",
                    params = list(id))
    DBI::dbCommit(admin)
    result <- await_result(waiting)
    stopifnot(identical(result$kind, "poll_conflict"), sum(poll_summary(db, id)$responses) == 0L)
    id <- make_poll("Response first")
    choice <- choices_for(id)[[1]]
    lock_poll(id)
    waiting <- spawn_worker("close", id, suffix = "response-first")
    wait_blocked(1L)
    DBI::dbExecute(admin, "UPDATE poll_studio.polls SET response_count = response_count + 1 WHERE id = $1::bigint",
                    params = list(id))
    DBI::dbExecute(admin,
      "INSERT INTO poll_studio.responses (poll_id, choice_id, participant_code) VALUES ($1::bigint, $2::bigint, 'BEFORE_CLOSE')",
      params = list(id, choice))
    DBI::dbCommit(admin)
    stopifnot(isTRUE(await_result(waiting)$closed), sum(poll_summary(db, id)$responses) == 1L,
              all(poll_summary(db, id)$closed))
    stopifnot(record_response(db, id, choice, "BEFORE_CLOSE")$replayed)
  })

  cloud_check("response cap, Unicode bounds and bounded newest poll list", function() {
    id <- make_poll("Capacity")
    choice <- choices_for(id)[[1]]
    record_response(db, id, choice, "RETAINED_CAP")
    DBI::dbExecute(owner, "UPDATE poll_studio.polls SET response_count = 10000 WHERE id = $1::bigint", params = list(id))
    expect_error(function() record_response(db, id, choice, "OVER_CAP"), "poll_conflict")
    stopifnot(record_response(db, id, choice, "RETAINED_CAP")$replayed)
    # Owner-only cap acceleration; restore the truthful stored counter afterward.
    DBI::dbExecute(owner, "UPDATE poll_studio.polls SET response_count = 1 WHERE id = $1::bigint", params = list(id))
    id <- create_poll(db, paste(rep("é", 200), collapse = ""), c("🌱", "Paper"))
    stopifnot(nchar(poll_summary(db, id)$question[[1]]) == 200L)
    for (i in seq_len(102L)) create_poll(db, paste("Bound fixture", i), c("One", "Two"))
    rows <- list_polls(db)
    stopifnot(nrow(rows) == 100L, !anyDuplicated(rows$id))
  })

  cloud_check("certificate-specific CA and hostname failures with positive control", function() {
    ca <- file.path(evidence, "wrong-ca.pem")
    key <- file.path(evidence, "wrong-ca.key")
    status <- system2("openssl", c("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
      "-subj", shQuote("/CN=Wrong Test CA"), "-keyout", shQuote(key), "-out", shQuote(ca)),
      stdout = FALSE, stderr = FALSE)
    stopifnot(status == 0L)
    wrong <- opts
    wrong$sslrootcert <- ca
    error <- assert_db_error(function() do.call(DBI::dbConnect, wrong), "certificate verify failed")
    cat("Wrong CA: certificate verify failed\n")
    wrong <- opts
    # Use the verified endpoint's DNS resolution, not the database's internal address.
    address <- system2("getent", c("ahostsv4", shQuote(opts$host)), stdout = TRUE)
    wrong$hostaddr <- strsplit(address[[1]], "[[:space:]]+")[[1]][[1]]
    wrong$host <- "wrong-hostname.example.test"
    assert_db_error(function() do.call(DBI::dbConnect, wrong), "does not match host name")
    cat("Wrong hostname: real endpoint certificate does not match configured host\n")
    positive <- do.call(DBI::dbConnect, opts)
    stopifnot(DBI::dbGetQuery(positive, "SELECT 1 AS n")$n == 1L)
    DBI::dbDisconnect(positive)
    unlink(c(ca, key))
  })
  cat("Cloud acceptance: 7 checks passed\n")
}, finally = {
  try(DBI::dbRollback(admin), silent = TRUE)
  for (table in c("choices", "responses")) {
    name <- if (table == "choices") "reject_test_choice" else "reject_test_response"
    try(DBI::dbExecute(owner, paste0("DROP TRIGGER IF EXISTS ", name, " ON poll_studio.", table)), silent = TRUE)
    try(DBI::dbExecute(owner, paste0("DROP FUNCTION IF EXISTS poll_studio.", name, "()")), silent = TRUE)
  }
  DBI::dbDisconnect(admin)
  DBI::dbDisconnect(owner)
  pool::poolClose(db)
})
