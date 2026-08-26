# Rendering: builds the briefing payload (at-a-glance strip, charts,
# rule-based commentary, data table) and renders the one-page PDF via Quarto.
# Commentary is template-based from computed numbers only: describe, don't
# forecast, don't editorialise. No LLM call at runtime.

ATTRIBUTION <- paste(
  "Basic data: Statistics South Africa. Users may apply the information as",
  "they wish, provided they acknowledge Stats SA as the source of the basic",
  "data, and specify that the relevant application and analysis result from",
  "their own processing of the data.")

#' Direction word for template sentences (threshold: 0.05 rounds to same 0,1).
dir_word <- function(now, prior) {
  if (is.na(now) || is.na(prior)) return("compared with")
  d <- round(now, 1) - round(prior, 1)
  if (d > 0) "up from" else if (d < 0) "down from" else "unchanged from"
}

#' South African percentage in prose: decimal comma, "4,3%".
pct_za <- function(x, digits = 1) {
  ifelse(is.na(x), "not available", paste0(format_za(x, digits), "%"))
}

revision_note <- function(revisions) {
  if (is.null(revisions) || nrow(revisions) == 0) {
    return("No revisions to previously published values were detected.")
  }
  ex <- utils::head(revisions, 3)
  det <- paste(sprintf("%s %s revised from %s to %s", ex$series_code, ex$period,
                       format_za(ex$old, 1), format_za(ex$new, 1)), collapse = "; ")
  sprintf("Revisions detected in %d observation(s): %s.", nrow(revisions), det)
}

#' Assemble the CPI briefing payload.
payload_cpi <- function(t, root = here::here()) {
  h <- t$headline
  glance <- list(
    list(label = "Headline y/y", value = pct_za(h$yy)),
    list(label = "m/m", value = pct_za(h$mm)),
    list(label = "Core y/y", value = pct_za(h$core_yy)),
    list(label = "Index (Dec 2024 = 100)", value = format_za(h$index, 1))
  )

  cm <- c(
    sprintf("Headline consumer inflation was %s y/y in %s, %s %s in %s.",
            pct_za(h$yy), t$label, dir_word(h$yy, h$yy_prior),
            pct_za(h$yy_prior), period_label(period_lag(t$period, 1))),
    sprintf("The index rose %s m/m to %s (Dec 2024 = 100).",
            pct_za(h$mm), format_za(h$index, 1)),
    sprintf("Core inflation (CPI excluding food and NAB, fuel and energy) was %s y/y, %s %s.",
            pct_za(h$core_yy), dir_word(h$core_yy, h$core_yy_prior),
            pct_za(h$core_yy_prior))
  )
  top <- utils::head(t$divisions, 2); bot <- utils::tail(t$divisions, 1)
  cm <- c(cm, sprintf(
    "Among divisions, %s (%s) and %s (%s) recorded the fastest annual increases; %s (%s) the slowest.",
    top$name[1], pct_za(top$yy[1]), top$name[2], pct_za(top$yy[2]),
    bot$name[1], pct_za(bot$yy[1])))
  if (!is.null(t$breadth_now) && !is.na(t$breadth_now)) {
    cm <- c(cm, sprintf(
      "Prices covering %s of the CPI basket by weight were inflating faster than the 4,5%% midpoint (as at %s).",
      pct_za(t$breadth_now, 0), t$breadth_asof))
  }
  cm <- c(cm, t$flags)

  tbl <- data.frame(
    Division = t$divisions$name,
    `y/y %` = format_za(t$divisions$yy, 1),
    check.names = FALSE
  )
  if (!is.null(t$contributions)) {
    m <- match(t$divisions$key, t$contributions$key)
    tbl$`Contribution pp` <- ifelse(is.na(m), "",
                                    format_za(t$contributions$pp[m], 2))
    tbl$`Weight` <- ifelse(is.na(m), "", format_za(t$contributions$weight[m], 2))
  }

  charts <- c(
    save_chart(chart_cpi_headline_core(t),
               file.path(root, "output", "charts", sprintf("cpi_%s_headline.png", t$period)),
               width = 3.45, height = 2.5),
    save_chart(chart_cpi_divisions(t),
               file.path(root, "output", "charts", sprintf("cpi_%s_divisions.png", t$period)),
               width = 3.45, height = 2.5)
  )

  list(release = "cpi", period = t$period, label = t$label,
       title = sprintf("Consumer Price Index — %s", t$label),
       source_line = "Statistics South Africa, P0141 (Consumer Price Index)",
       glance = glance, charts = charts, commentary = cm, table = tbl,
       retrieved = t$vintage[[1]]$retrieved_at,
       vintage_source = t$vintage[[1]]$source %||% "statssa",
       revision_note = revision_note(t$revisions),
       attribution = ATTRIBUTION)
}

#' Locate the Quarto binary: PATH first, then the RStudio-bundled copy.
ensure_quarto <- function() {
  if (nzchar(Sys.getenv("QUARTO_PATH"))) return(invisible(TRUE))
  found <- Sys.which("quarto")
  if (nzchar(found)) return(invisible(TRUE))
  bundled <- "/Applications/RStudio.app/Contents/Resources/app/quarto/bin/quarto"
  if (file.exists(bundled)) {
    Sys.setenv(QUARTO_PATH = bundled)
    return(invisible(TRUE))
  }
  stop("Quarto CLI not found; install Quarto or set QUARTO_PATH", call. = FALSE)
}

#' Render a payload to output/{release}_{period}.pdf. Deterministic: the PDF
#' creation date is pinned to the data vintage (SOURCE_DATE_EPOCH), so two
#' runs over the same inputs are byte-identical.
render_brief <- function(payload, root = here::here()) {
  ensure_quarto()
  dir.create(file.path(root, "output"), recursive = TRUE, showWarnings = FALSE)
  payload_path <- file.path(root, "output", sprintf("payload_%s_%s.rds",
                                                    payload$release, payload$period))
  saveRDS(payload, payload_path)

  epoch <- tryCatch(
    as.integer(lubridate::ymd_hms(payload$retrieved, tz = "UTC", quiet = TRUE)),
    error = function(e) NA_integer_)
  old_epoch <- Sys.getenv("SOURCE_DATE_EPOCH", unset = NA)
  if (!is.na(epoch)) Sys.setenv(SOURCE_DATE_EPOCH = epoch)
  on.exit({
    if (is.na(old_epoch)) Sys.unsetenv("SOURCE_DATE_EPOCH")
    else Sys.setenv(SOURCE_DATE_EPOCH = old_epoch)
  }, add = TRUE)

  out_name <- sprintf("%s_%s.pdf", payload$release, gsub("[^A-Za-z0-9]", "", payload$period))
  quarto::quarto_render(
    input = file.path(root, "inst", "quarto", "brief.qmd"),
    output_file = out_name,
    execute_params = list(payload = payload_path),
    quiet = TRUE
  )
  rendered <- file.path(root, "inst", "quarto", out_name)
  final <- file.path(root, "output", out_name)
  file.rename(rendered, final)
  message("Briefing written to ", final)
  invisible(final)
}
