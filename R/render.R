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
  if (!is.null(t$breadth)) {
    charts <- c(charts,
      save_chart(chart_cpi_breadth(t),
                 file.path(root, "output", "charts", sprintf("cpi_%s_breadth.png", t$period)),
                 width = 3.2, height = 2.2))
  }

  list(release = "cpi", period = t$period, label = t$label,
       title = sprintf("Consumer Price Index — %s", t$label),
       source_line = "Statistics South Africa, P0141 (Consumer Price Index)",
       glance = glance, charts = charts, commentary = cm, table = tbl,
       retrieved = t$vintage[[1]]$retrieved_at,
       vintage_source = t$vintage[[1]]$source %||% "statssa",
       revision_note = revision_note(t$revisions),
       attribution = ATTRIBUTION)
}

#' Locate the Quarto binary: an explicit QUARTO_PATH, then PATH, then the
#' copy bundled with RStudio on each platform. Many users have Quarto only
#' via RStudio and no standalone install.
quarto_candidates <- function() {
  c(
    # macOS
    "/Applications/RStudio.app/Contents/Resources/app/quarto/bin/quarto",
    "/Applications/RStudio.app/Contents/MacOS/quarto/bin/quarto",
    "/usr/local/bin/quarto", "/opt/homebrew/bin/quarto",
    # Linux
    "/usr/lib/rstudio/resources/app/bin/quarto/bin/quarto",
    "/usr/lib/rstudio/bin/quarto/bin/quarto",
    "/usr/lib/rstudio-server/bin/quarto/bin/quarto",
    "/opt/quarto/bin/quarto", "/usr/bin/quarto",
    # Windows
    file.path(Sys.getenv("LOCALAPPDATA", ""), "Programs", "Quarto", "bin", "quarto.exe"),
    "C:/Program Files/RStudio/resources/app/bin/quarto/bin/quarto.exe",
    "C:/Program Files/Quarto/bin/quarto.exe"
  )
}

ensure_quarto <- function() {
  if (nzchar(Sys.getenv("QUARTO_PATH"))) return(invisible(TRUE))
  found <- Sys.which("quarto")
  if (nzchar(found)) return(invisible(TRUE))
  for (cand in quarto_candidates()) {
    if (nzchar(cand) && file.exists(cand)) {
      Sys.setenv(QUARTO_PATH = cand)
      return(invisible(TRUE))
    }
  }
  stop("Quarto CLI not found. Install it from https://quarto.org/docs/download/ ",
       "or set QUARTO_PATH to the binary. Searched PATH and: ",
       paste(Filter(nzchar, quarto_candidates()), collapse = ", "),
       call. = FALSE)
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

# ---------------------------------------------------------------------------
# PPI payload

payload_ppi <- function(t, root = here::here()) {
  h <- t$headline
  glance <- list(
    list(label = "PPI y/y", value = pct_za(h$yy)),
    list(label = "m/m", value = pct_za(h$mm)),
    list(label = "Index (Dec 2023 = 100)", value = format_za(h$index, 1)),
    list(label = "CPI y/y (same month)", value = pct_za(h$cpi_yy))
  )
  cm <- c(
    sprintf("Producer inflation for final manufactured goods was %s y/y in %s, %s %s in %s.",
            pct_za(h$yy), t$label, dir_word(h$yy, h$yy_prior),
            pct_za(h$yy_prior), period_label(period_lag(t$period, 1))),
    sprintf("The index moved %s m/m to %s (Dec 2023 = 100).",
            pct_za(h$mm), format_za(h$index, 1)))
  if (!is.na(h$cpi_yy)) {
    gap <- h$yy - h$cpi_yy
    cm <- c(cm, sprintf(
      "Producer inflation ran %s pp %s consumer inflation (%s y/y) in the same month.",
      format_za(abs(gap), 1), if (gap >= 0) "above" else "below", pct_za(h$cpi_yy)))
  }
  cm <- c(cm, t$flags)

  mmtab <- utils::tail(t$mm_history, 6)
  tbl <- data.frame(Month = vapply(mmtab$period, period_label, ""),
                    `m/m %` = format_za(mmtab$mm, 1), check.names = FALSE)

  charts <- c(
    save_chart(chart_ppi_vs_cpi(t),
               file.path(root, "output", "charts", sprintf("ppi_%s_vs_cpi.png", t$period)),
               width = 3.45, height = 2.5),
    save_chart(chart_ppi_mm(t),
               file.path(root, "output", "charts", sprintf("ppi_%s_mm.png", t$period)),
               width = 3.45, height = 2.5)
  )

  list(release = "ppi", period = t$period, label = t$label,
       title = sprintf("Producer Price Index — %s", t$label),
       source_line = "Statistics South Africa, P0142.1 (Producer Price Index)",
       glance = glance, charts = charts, commentary = cm, table = tbl,
       retrieved = t$vintage[[1]]$retrieved_at,
       vintage_source = t$vintage[[1]]$source %||% "statssa",
       revision_note = revision_note(t$revisions),
       attribution = ATTRIBUTION)
}

# ---------------------------------------------------------------------------
# GDP payload

payload_gdp <- function(t, root = here::here()) {
  h <- t$headline
  glance <- list(
    list(label = "GDP q/q (sa)", value = pct_za(h$qq)),
    list(label = "y/y", value = pct_za(h$yy)),
    list(label = "Prior quarter q/q", value = pct_za(h$qq_prior)),
    list(label = "Level (sa&a, R million)", value = format_za(h$level, 0))
  )
  top <- t$contributions[order(t$contributions$pp, decreasing = TRUE), ]
  pos <- utils::head(top[top$pp > 0, ], 2)
  neg <- utils::head(top[order(top$pp), ][top[order(top$pp), ]$pp < 0, ], 1)
  cm <- c(
    sprintf("Real GDP grew %s q/q (seasonally adjusted, not annualised) in %s, %s %s in the prior quarter.",
            pct_za(h$qq), t$label, dir_word(h$qq, h$qq_prior), pct_za(h$qq_prior)),
    sprintf("Output was %s higher than a year earlier (unadjusted).", pct_za(h$yy)))
  if (nrow(pos) > 0) {
    cm <- c(cm, sprintf("%s (%s pp)%s contributed most to growth.",
                        pos$name[1], format_za(pos$pp[1], 1),
                        if (nrow(pos) > 1) sprintf(" and %s (%s pp)", pos$name[2], format_za(pos$pp[2], 1)) else ""))
  }
  if (nrow(neg) > 0) {
    cm <- c(cm, sprintf("%s subtracted %s pp.", neg$name[1], format_za(abs(neg$pp[1]), 1)))
  }
  cm <- c(cm, t$flags)

  tc <- t$contributions[order(t$contributions$pp, decreasing = TRUE), ]
  tbl <- data.frame(Component = tc$name,
                    `Contribution pp` = format_za(tc$pp, 2), check.names = FALSE)

  charts <- c(
    save_chart(chart_gdp_qq(t),
               file.path(root, "output", "charts", sprintf("gdp_%s_qq.png", t$period)),
               width = 3.45, height = 2.5),
    save_chart(chart_gdp_contributions(t),
               file.path(root, "output", "charts", sprintf("gdp_%s_contrib.png", t$period)),
               width = 3.45, height = 2.5)
  )

  list(release = "gdp", period = t$period, label = t$label,
       title = sprintf("Gross Domestic Product — %s", t$label),
       source_line = "Statistics South Africa, P0441 (Gross Domestic Product)",
       glance = glance, charts = charts, commentary = cm, table = tbl,
       retrieved = t$vintage[[1]]$retrieved_at,
       vintage_source = t$vintage[[1]]$source %||% "statssa",
       revision_note = revision_note(t$revisions),
       attribution = ATTRIBUTION)
}

# ---------------------------------------------------------------------------
# QLFS payload

payload_qlfs <- function(t, root = here::here()) {
  a <- t$table_a
  g <- function(k, col = "q_now") a[a$key == k, col]
  glance <- list(
    list(label = "LU1 unemployment rate", value = pct_za(g("lu1"))),
    list(label = "LU3 (incl potential labour force)", value = pct_za(g("lu3"))),
    list(label = "Employment q/q", value = paste0(format_za(g("employed", "qq_change"), 0), "k")),
    list(label = "Absorption rate", value = pct_za(g("absorption_rate")))
  )
  cm <- c(
    sprintf("The official unemployment rate (LU1) was %s in %s, a change of %s pp on the quarter.",
            pct_za(g("lu1")), t$label, format_za(g("lu1", "qq_pp"), 1)),
    sprintf("LU3, which combines unemployment with the potential labour force, was %s (%s pp q/q); reporting both is necessary because neither alone represents the South African labour market.",
            pct_za(g("lu3")), format_za(g("lu3", "qq_pp"), 1)),
    sprintf("Employment was %s thousand (%s thousand q/q); the absorption rate was %s and participation %s.",
            format_za(g("employed"), 0), format_za(g("employed", "qq_change"), 0),
            pct_za(g("absorption_rate")), pct_za(g("participation_rate"))),
    "Figures cover persons aged 15-64. Informal/formal sector estimates follow the 21st ICLS standard and are comparable only from Q3 2025 onward.")
  cm <- c(cm, t$flags)

  ic <- t$industry_changes[order(t$industry_changes$change, decreasing = TRUE), ]
  tbl <- data.frame(Industry = ic$name,
                    `Level (thousand)` = format_za(ic$level, 0),
                    `q/q change` = format_za(ic$change, 0),
                    `y/y change` = format_za(ic$yy_change, 0),
                    check.names = FALSE)

  charts <- c(
    save_chart(chart_qlfs_rates(t),
               file.path(root, "output", "charts", sprintf("qlfs_%s_rates.png", t$period)),
               width = 3.45, height = 2.5),
    save_chart(chart_qlfs_employment(t),
               file.path(root, "output", "charts", sprintf("qlfs_%s_industry.png", t$period)),
               width = 3.45, height = 2.5)
  )

  list(release = "qlfs", period = t$period, label = t$label,
       title = sprintf("Quarterly Labour Force Survey — %s", t$label),
       source_line = "Statistics South Africa, P0211 (Quarterly Labour Force Survey)",
       glance = glance, charts = charts, commentary = cm, table = tbl,
       retrieved = t$vintage[[1]]$retrieved_at,
       vintage_source = t$vintage[[1]]$source %||% "statssa",
       revision_note = "QLFS estimates are not revised between releases; series breaks are documented in config/series_breaks.yaml.",
       attribution = ATTRIBUTION)
}
