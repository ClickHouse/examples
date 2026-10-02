// Render actionable HTML for conflicts and transient database errors too.
document.addEventListener("htmx:beforeSwap", function (event) {
  if ([409, 503].includes(event.detail.xhr.status)) {
    event.detail.shouldSwap = true;
    event.detail.isError = false;
  }
});
