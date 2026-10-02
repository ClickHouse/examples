source("R/database.R")
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 1L)
conn <- do.call(DBI::dbConnect, connection_options())
result <- DBI::dbGetQuery(conn,
  "SELECT count(*)::integer AS n FROM poll_studio.polls WHERE question = $1", params = list(args[[1]]))
DBI::dbDisconnect(conn)
cat(jsonlite::toJSON(result$n[[1]], auto_unbox = TRUE))
