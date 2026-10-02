source("R/validation.R")
expect_error <- function(action, class = "poll_error") {
  result <- tryCatch({ action(); NULL }, error = identity)
  stopifnot(inherits(result, class))
}
check <- function(name, action) {
  action()
  cat("PASS:", name, "\n")
}
check("bounded trimmed Unicode question and distinct choices", function() {
  x <- validate_poll("  A small question  ", c(" Garden ", "Paper"))
  stopifnot(identical(x$question, "A small question"), identical(x$choices, c("Garden", "Paper")))
  stopifnot(nchar(validate_poll(paste(rep("é", 200), collapse = ""), c("A", "B"))$question) == 200)
  expect_error(function() validate_poll(paste(rep("é", 201), collapse = ""), c("A", "B")))
})
check("malformed polls and control characters reject", function() {
  for (choices in list("One", rep("x", 9), c(" A ", "A"), c("A", "\nB"), c("", "B"))) {
    expect_error(function() validate_poll("Question", choices))
  }
  expect_error(function() validate_poll(list("not text"), c("A", "B")))
})
check("synthetic codes normalize and exclude unsupported characters", function() {
  stopifnot(identical(participant_code(" sample_001 "), "SAMPLE_001"))
  for (value in c("AB", "A B", "a@b", "\tSAMPLE", paste(rep("A", 33), collapse = ""))) {
    expect_error(function() participant_code(value))
  }
})
check("identifiers preserve bigint precision and signed range", function() {
  stopifnot(identical(identifier("9223372036854775807"), "9223372036854775807"))
  for (value in list("9223372036854775808", "0", "1e3", 1, "1; DROP TABLE", NA_character_)) {
    expect_error(function() identifier(value))
  }
})
check("actual request Origin requires exact configured loopback value", function() {
  expected <- "http://127.0.0.1:4000"
  stopifnot(trusted_origin(list(HTTP_ORIGIN = expected), expected))
  for (value in list(NULL, "null", "http://localhost:4000", "http://127.0.0.1:4001",
                    "https://example.test", c(expected, "https://example.test"))) {
    stopifnot(!trusted_origin(list(HTTP_ORIGIN = value), expected))
  }
})
cat("Domain acceptance: 5 checks passed\n")
