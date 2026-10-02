library(shiny)
source("R/validation.R")
source("R/database.R")
source("R/polls.R")

port <- suppressWarnings(as.integer(Sys.getenv("PORT", "4000")))
if (is.na(port) || port < 1L || port > 65535L) stop("Invalid PORT")
expected_origin <- required_env("APP_ORIGIN")
if (!identical(expected_origin, paste0("http://127.0.0.1:", port))) {
  stop("APP_ORIGIN must match the fixed loopback listener origin.")
}
if (!identical(required_env("PGUSER"), "polls_app")) stop("Start with the runtime role.")
db <- new_pool()
onStop(function() pool::poolClose(db))

ui <- fluidPage(
  tags$head(tags$link(rel = "stylesheet", href = "style.css")),
  div(class = "page-shell",
    div(class = "masthead", span(class = "brand", "Poll studio"),
        span(class = "badge", "Synthetic workbench")),
    div(class = "intro", p(class = "eyebrow", "A small decision, made visible"),
        h1("Make room for a choice."),
        p("Create a question, record sample responses and see the count take shape.")),
    div(class = "workspace",
      div(class = "panel", h2("Start a poll"),
          textInput("question", "Question", placeholder = "What should our imaginary team try?"),
          textAreaInput("choice_lines", "Choices, one per line", rows = 4,
                        placeholder = "Paper planets\nTiny gardens\nQuiet circuits"),
          actionButton("create", "Create poll", class = "primary"),
          p(class = "hint", "Two to eight distinct choices. No personal information.")),
      div(class = "panel", h2("Record a response"),
          selectInput("poll_id", "Stored poll", choices = character(), selectize = FALSE),
          uiOutput("poll_state"),
          radioButtons("choice_id", "Choose an option", choices = character(), selected = character()),
          textInput("code", "Synthetic participant code", placeholder = "SAMPLE_001"),
          actionButton("respond", "Save response", class = "primary"),
          p(class = "hint", "Codes deduplicate responses; they do not identify people."),
          verbatimTextOutput("last_result", placeholder = FALSE)),
      div(class = "panel results", h2("The count so far"),
          div(class = "toolbar", actionButton("refresh", "Refresh stored counts"),
              actionButton("close", "Close selected poll")),
          textOutput("summary_heading"),
          plotOutput("counts", height = "260px"),
          tableOutput("count_table"),
          p(class = "hint", "Refresh to see another browser’s committed responses. Charts show counts only."))
    ),
    div(class = "footnote", "Trusted local operators share authority. A matching saved response replays after closure; a different choice conflicts.")
  )
)

server <- function(input, output, session) {
  # Check the actual WebSocket request before registering database observers.
  if (!trusted_origin(session$request, expected_origin)) {
    session$close()
    return(invisible(NULL))
  }
  changed <- reactiveVal(0L)
  last_result <- reactiveVal("")
  pending_selection <- reactiveVal(NULL)
  refresh <- function() changed(isolate(changed()) + 1L)
  safely <- function(action) {
    tryCatch(action(), poll_error = function(error) {
      showNotification(conditionMessage(error), type = "warning")
    }, error = function(error) {
      showNotification("The database operation could not complete. Please retry.", type = "error")
    })
  }
  stored_polls <- reactive({ changed(); list_polls(db) })
  observe({
    rows <- stored_polls()
    selected <- isolate(pending_selection())
    if (is.null(selected)) selected <- isolate(input$poll_id)
    choices <- setNames(rows$id, paste0(rows$question, ifelse(rows$closed, " · closed", " · open")))
    if (length(selected) != 1L || is.na(selected) || !selected %in% rows$id) {
      selected <- if (nrow(rows)) rows$id[[1]] else character()
    }
    updateSelectInput(session, "poll_id", choices = choices, selected = selected)
  })
  summary <- reactive({
    changed()
    req(isTruthy(input$poll_id))
    poll_summary(db, input$poll_id)
  })
  observe({
    rows <- summary()
    selected <- isolate(input$choice_id)
    if (length(selected) != 1L || is.na(selected) || !selected %in% rows$choice_id) {
      selected <- if (nrow(rows)) rows$choice_id[[1]] else character()
    }
    updateRadioButtons(session, "choice_id", choices = setNames(rows$choice_id, rows$label), selected = selected)
  })
  output$poll_state <- renderUI({
    rows <- summary()
    req(nrow(rows) > 0L)
    div(class = if (rows$closed[[1]]) "state closed" else "state open",
        if (rows$closed[[1]]) "Closed · saved matches can replay" else "Open · accepting sample responses")
  })
  output$last_result <- renderText(last_result())
  output$summary_heading <- renderText({
    rows <- summary()
    req(nrow(rows) > 0L)
    paste(rows$question[[1]], "—", sum(rows$responses), "saved responses")
  })
  output$counts <- renderPlot({
    rows <- summary()
    req(nrow(rows) > 0L)
    par(mar = c(4, 10, 1, 1), bg = "#ffffff")
    labels <- ifelse(nchar(rows$label) > 18L, paste0(substr(rows$label, 1L, 17L), "…"), rows$label)
    barplot(rows$responses, names.arg = labels, col = "#467763", border = NA,
            horiz = TRUE, xlab = "Responses", xlim = c(0, max(1, rows$responses) + 1),
            las = 1, cex.names = 0.8)
  })
  output$count_table <- renderTable({
    rows <- summary()
    data.frame(Choice = rows$label, Count = rows$responses)
  }, rownames = FALSE, width = "100%")
  observeEvent(input$create, safely(function() {
    lines <- choice_lines(input$choice_lines)
    id <- create_poll(db, input$question, lines)
    pending_selection(id)
    refresh()
    updateTextInput(session, "question", value = "")
    updateTextAreaInput(session, "choice_lines", value = "")
    showNotification("Poll and choices saved.", type = "message")
  }))
  observeEvent(input$poll_id, {
    if (identical(input$poll_id, isolate(pending_selection()))) pending_selection(NULL)
  })
  observeEvent(input$respond, safely(function() {
    result <- record_response(db, input$poll_id, input$choice_id, input$code)
    last_result(if (result$replayed) "Matching saved response replayed." else "Response saved once.")
    refresh()
  }))
  observeEvent(input$close, safely(function() {
    close_poll(db, input$poll_id)
    refresh()
    showNotification("Poll closed. Saved matching responses remain repeatable.", type = "message")
  }))
  observeEvent(input$refresh, safely(refresh))
}

shinyApp(ui, server)
