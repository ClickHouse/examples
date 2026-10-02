port <- suppressWarnings(as.integer(Sys.getenv("PORT", "4000")))
if (is.na(port) || port < 1L || port > 65535L) stop("Invalid PORT")
options(shiny.sanitize.errors = TRUE, shiny.maxRequestSize = 65536)
tryCatch(
  shiny::runApp(".", host = "127.0.0.1", port = port, launch.browser = FALSE),
  interrupt = function(error) message("Poll Studio stopped after interrupt")
)
