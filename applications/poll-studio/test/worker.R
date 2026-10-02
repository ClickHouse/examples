source("R/validation.R")
source("R/database.R")
source("R/polls.R")
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 5L)
options <- connection_options()
# Independent contention fixtures may hold a lock longer than the interactive timeout.
options$options <- "-c statement_timeout=30000 -c lock_timeout=30000 -c idle_in_transaction_session_timeout=30000"
db <- do.call(pool::dbPool, c(options, list(minSize = 1L, maxSize = 1L)))
result <- tryCatch({
  if (args[[1]] == "respond") {
    record_response(db, args[[2]], args[[3]], args[[4]])
  } else if (args[[1]] == "close") {
    close_poll(db, args[[2]])
    list(closed = TRUE)
  } else stop("Unknown test task")
}, poll_error = function(error) list(error = conditionMessage(error), kind = class(error)[[1]]),
   error = function(error) list(error = "unexpected database error", kind = "unexpected"))
pool::poolClose(db)
temporary <- paste0(args[[5]], ".tmp")
jsonlite::write_json(result, temporary, auto_unbox = TRUE)
stopifnot(file.rename(temporary, args[[5]]))
