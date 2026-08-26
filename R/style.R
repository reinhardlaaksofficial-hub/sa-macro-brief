# One house style for every chart. One accent colour; comparison series wear
# dark ink with a distinct linetype plus direct labels, so identity never
# rides on hue alone. Muted gridlines, no chart junk, no pie charts.

BRIEF_ACCENT <- "#0F6E63"   # deep teal: the single accent
BRIEF_INK    <- "#1F1F28"   # near-black ink for text and comparison series
BRIEF_GREY   <- "#8A8A93"   # muted: gridline text, de-emphasised marks
BRIEF_GRID   <- "#E3E3E0"   # gridlines
BRIEF_BAND   <- "#0F6E63"   # target band shading uses the accent at low alpha

theme_brief <- function(base_size = 9) {
  ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(
      text = ggplot2::element_text(colour = BRIEF_INK),
      plot.title = ggplot2::element_text(face = "bold", size = base_size + 1),
      plot.subtitle = ggplot2::element_text(colour = BRIEF_GREY, size = base_size - 1),
      plot.caption = ggplot2::element_text(colour = BRIEF_GREY, size = base_size - 2,
                                           hjust = 0),
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major = ggplot2::element_line(colour = BRIEF_GRID, linewidth = 0.3),
      axis.title = ggplot2::element_blank(),
      axis.text = ggplot2::element_text(colour = BRIEF_GREY, size = base_size - 1),
      legend.position = "none",
      plot.title.position = "plot",
      plot.caption.position = "plot",
      plot.margin = ggplot2::margin(4, 8, 4, 4)
    )
}

#' Standard source caption. Every chart carries the code and retrieval date.
source_caption <- function(code, retrieved) {
  sprintf("Source: Statistics South Africa, %s. Retrieved %s.", code, retrieved)
}

#' Save a chart deterministically (fixed device, size, dpi; no timestamps).
save_chart <- function(plot, path, width = 3.3, height = 2.3, dpi = 300) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  ragg::agg_png(path, width = width, height = height, units = "in", res = dpi)
  print(plot)
  grDevices::dev.off()
  invisible(path)
}
