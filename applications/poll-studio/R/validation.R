poll_error <- function(message, kind = "validation") {
  stop(structure(list(message = message, call = NULL),
                 class = c(paste0("poll_", kind), "poll_error", "error", "condition")))
}

bounded_text <- function(value, maximum, field) {
  if (!is.character(value) || length(value) != 1L || is.na(value) ||
      grepl("[[:cntrl:]]", value)) {
    poll_error(paste(field, "must be text without control characters."))
  }
  value <- trimws(value)
  if (nchar(value, type = "chars") < 1L || nchar(value, type = "chars") > maximum) {
    poll_error(paste(field, "is outside its length limit."))
  }
  value
}

validate_poll <- function(question, choices) {
  question <- bounded_text(question, 200L, "Question")
  if (!is.character(choices) || length(choices) < 2L || length(choices) > 8L) {
    poll_error("Use two through eight choices.")
  }
  choices <- vapply(choices, bounded_text, character(1), maximum = 80L, field = "Choice")
  if (anyDuplicated(choices)) poll_error("Choice labels must be distinct after trimming.")
  list(question = question, choices = unname(choices))
}

identifier <- function(value) {
  if (!is.character(value) || length(value) != 1L || is.na(value) ||
      !grepl("^[1-9][0-9]{0,18}$", value) ||
      (nchar(value) == 19L && value > "9223372036854775807")) {
    poll_error("Choose a valid stored poll or choice.")
  }
  value
}

participant_code <- function(value) {
  value <- toupper(bounded_text(value, 32L, "Participant code"))
  if (!grepl("^[A-Z0-9][A-Z0-9_-]{2,31}$", value)) {
    poll_error("Use a synthetic code of 3–32 letters, digits, underscores or hyphens.")
  }
  value
}

trusted_origin <- function(request, expected) {
  origin <- request$HTTP_ORIGIN
  is.character(origin) && length(origin) == 1L && !is.na(origin) && identical(origin, expected)
}

choice_lines <- function(value) {
  if (!is.character(value) || length(value) != 1L || is.na(value) ||
      nchar(value, type = "chars") > 1024L) {
    poll_error("Choice input must be at most 1,024 characters.")
  }
  strsplit(value, "\n", fixed = TRUE)[[1]]
}
