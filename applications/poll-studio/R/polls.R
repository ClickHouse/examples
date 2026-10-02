create_poll <- function(db, question, choices) {
  input <- validate_poll(question, choices)
  pool::poolWithTransaction(db, function(conn) {
    row <- DBI::dbGetQuery(conn,
      "INSERT INTO poll_studio.polls (question) VALUES ($1) RETURNING id::text AS id",
      params = list(input$question))
    for (position in seq_along(input$choices)) {
      DBI::dbExecute(conn,
        "INSERT INTO poll_studio.choices (poll_id, position, label) VALUES ($1::bigint, $2, $3)",
        params = list(row$id[[1]], position, input$choices[[position]]))
    }
    row$id[[1]]
  })
}

list_polls <- function(db) {
  DBI::dbGetQuery(db,
    "SELECT id::text AS id, question, closed_at IS NOT NULL AS closed, response_count,
       created_at FROM poll_studio.polls ORDER BY created_at DESC, poll_studio.polls.id DESC LIMIT 100")
}

poll_summary <- function(db, poll_id) {
  poll_id <- identifier(poll_id)
  DBI::dbGetQuery(db,
    "SELECT p.id::text AS poll_id, p.question, p.closed_at IS NOT NULL AS closed,
       p.response_count, c.id::text AS choice_id, c.label, c.position,
       count(r.id)::integer AS responses
     FROM poll_studio.polls p JOIN poll_studio.choices c ON c.poll_id = p.id
       LEFT JOIN poll_studio.responses r ON r.poll_id = c.poll_id AND r.choice_id = c.id
     WHERE p.id = $1::bigint
     GROUP BY p.id, c.id ORDER BY c.position", params = list(poll_id))
}

record_response <- function(db, poll_id, choice_id, code) {
  poll_id <- identifier(poll_id)
  choice_id <- identifier(choice_id)
  code <- participant_code(code)
  pool::poolWithTransaction(db, function(conn) {
    poll <- DBI::dbGetQuery(conn,
      "SELECT closed_at IS NOT NULL AS closed, response_count FROM poll_studio.polls
       WHERE id = $1::bigint FOR UPDATE", params = list(poll_id))
    if (nrow(poll) == 0L) poll_error("Poll does not exist.", "missing")
    retained <- DBI::dbGetQuery(conn,
      "SELECT id::text AS id, choice_id::text AS choice_id FROM poll_studio.responses
       WHERE poll_id = $1::bigint AND participant_code = $2", params = list(poll_id, code))
    if (nrow(retained) > 0L) {
      if (!identical(retained$choice_id[[1]], choice_id)) {
        poll_error("This code already selected a different choice.", "conflict")
      }
      return(list(id = retained$id[[1]], replayed = TRUE))
    }
    if (poll$closed[[1]]) poll_error("Poll is closed; matching saved responses can still replay.", "conflict")
    if (poll$response_count[[1]] >= 10000L) poll_error("This poll reached its 10,000-response limit.", "conflict")
    choice <- DBI::dbGetQuery(conn,
      "SELECT id FROM poll_studio.choices WHERE poll_id = $1::bigint AND id = $2::bigint",
      params = list(poll_id, choice_id))
    if (nrow(choice) == 0L) poll_error("Choice does not belong to this poll.")
    DBI::dbExecute(conn,
      "UPDATE poll_studio.polls SET response_count = response_count + 1 WHERE id = $1::bigint",
      params = list(poll_id))
    row <- DBI::dbGetQuery(conn,
      "INSERT INTO poll_studio.responses (poll_id, choice_id, participant_code)
       VALUES ($1::bigint, $2::bigint, $3) RETURNING id::text AS id",
      params = list(poll_id, choice_id, code))
    list(id = row$id[[1]], replayed = FALSE)
  })
}

close_poll <- function(db, poll_id) {
  poll_id <- identifier(poll_id)
  pool::poolWithTransaction(db, function(conn) {
    row <- DBI::dbGetQuery(conn,
      "SELECT id FROM poll_studio.polls WHERE id = $1::bigint FOR UPDATE", params = list(poll_id))
    if (nrow(row) == 0L) poll_error("Poll does not exist.", "missing")
    DBI::dbExecute(conn,
      "UPDATE poll_studio.polls SET closed_at = COALESCE(closed_at, clock_timestamp())
       WHERE id = $1::bigint", params = list(poll_id))
    invisible(TRUE)
  })
}
