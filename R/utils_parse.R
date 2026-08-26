# Period and number parsing shared by all readers.
#
# Three period-column formats appear across the Stats SA H-code files:
#   CPI COICOP, PPI : "MO" + MM + YYYY   e.g. MO012008, MO072026
#   CPI 8-digit     : "M"  + YYYYMM      e.g. M200801
#   GDP             : YYYYQQ             e.g. 199301, 202601
# Requested periods on the CLI arrive as "2026-07" (monthly) or "2026Q1"
# (quarterly). parse_period() normalises all of these to a common form.

#' Parse a period token into a canonical period id.
#'
#' Returns a data.frame with columns:
#'   period : canonical string, "YYYY-MM" for monthly, "YYYYQn" for quarterly
#'   date   : first day of the period (Date)
#'   freq   : "monthly" or "quarterly"
#' Unrecognised tokens yield NA rows (never an error: callers decide whether
#' a stray column is fatal).
parse_period <- function(x) {
  x <- stringr::str_trim(as.character(x))
  n <- length(x)
  out <- data.frame(
    period = rep(NA_character_, n),
    date   = as.Date(rep(NA, n)),
    freq   = rep(NA_character_, n),
    stringsAsFactors = FALSE
  )

  set <- function(idx, year, sub, freq) {
    ok <- idx & !is.na(year) & !is.na(sub)
    if (freq == "monthly") {
      ok <- ok & sub >= 1 & sub <= 12
      out$period[ok] <<- sprintf("%04d-%02d", year[ok], sub[ok])
      out$date[ok]   <<- as.Date(sprintf("%04d-%02d-01", year[ok], sub[ok]))
    } else {
      ok <- ok & sub >= 1 & sub <= 4
      out$period[ok] <<- sprintf("%04dQ%d", year[ok], sub[ok])
      out$date[ok]   <<- as.Date(sprintf("%04d-%02d-01", year[ok], (sub[ok] - 1L) * 3L + 1L))
    }
    out$freq[ok] <<- freq
  }

  # "MO" + MM + YYYY (CPI COICOP, PPI)
  i <- stringr::str_detect(x, "^MO\\d{6}$") & !is.na(x)
  if (any(i)) {
    set(i, suppressWarnings(as.integer(substr(x, 5, 8))),
           suppressWarnings(as.integer(substr(x, 3, 4))), "monthly")
  }

  # "M" + YYYYMM (CPI 8-digit)
  i <- stringr::str_detect(x, "^M\\d{6}$") & !is.na(x)
  if (any(i)) {
    set(i, suppressWarnings(as.integer(substr(x, 2, 5))),
           suppressWarnings(as.integer(substr(x, 6, 7))), "monthly")
  }

  # YYYYQQ numeric (GDP): quarter encoded as 01-04
  i <- stringr::str_detect(x, "^(19|20)\\d{2}0[1-4]$") & !is.na(x)
  if (any(i)) {
    set(i, suppressWarnings(as.integer(substr(x, 1, 4))),
           suppressWarnings(as.integer(substr(x, 5, 6))), "quarterly")
  }

  # CLI monthly "YYYY-MM"
  i <- stringr::str_detect(x, "^\\d{4}-\\d{2}$") & !is.na(x)
  if (any(i)) {
    set(i, suppressWarnings(as.integer(substr(x, 1, 4))),
           suppressWarnings(as.integer(substr(x, 6, 7))), "monthly")
  }

  # CLI quarterly "YYYYQn" / "YYYYqn"
  i <- stringr::str_detect(x, "^\\d{4}[Qq][1-4]$") & !is.na(x)
  if (any(i)) {
    set(i, suppressWarnings(as.integer(substr(x, 1, 4))),
           suppressWarnings(as.integer(substr(x, 6, 6))), "quarterly")
  }

  out
}

#' Convenience: parse one period token, error if unrecognised.
parse_period_one <- function(x) {
  p <- parse_period(x)
  if (nrow(p) != 1L || is.na(p$period)) {
    stop("Unrecognised period token: ", x, call. = FALSE)
  }
  p
}

#' Parse Stats SA numeric tokens.
#'
#' Handles: decimal commas ("33,6") and decimal points ("107.7"),
#' space-separated thousands ("41 822", including non-breaking and thin
#' spaces), explicit minus variants, "..", "-" alone and "" as NA.
#' Anything else unparseable maps to NA (never zero) — the caller records
#' the failure, per the never-fabricate rule.
parse_number <- function(x) {
  x <- as.character(x)
  x <- stringr::str_replace_all(x, "[   ]", " ")
  x <- stringr::str_trim(x)
  x[x %in% c("", "..", ".", "-", "–", "N/A", "n/a", "*")] <- NA_character_
  # unify unicode minus, strip spaces inside numeric tokens (thousands seps)
  x <- stringr::str_replace_all(x, "−", "-")
  x <- stringr::str_remove_all(x, " ")
  # a comma is a decimal separator in Stats SA PDFs; the Excel files use points
  both <- stringr::str_detect(x, ",") & stringr::str_detect(x, "\\.")
  # if both appear (rare), treat the comma as thousands separator
  x[which(both)] <- stringr::str_remove_all(x[which(both)], ",")
  x <- stringr::str_replace(x, ",", ".")
  suppressWarnings(as.numeric(x))
}

#' Next period id in a series' own frequency ("2026-07" -> "2026-08").
period_next <- function(period) {
  p <- parse_period_one(period)
  if (p$freq == "monthly") {
    d <- seq(p$date, by = "month", length.out = 2)[2]
    format(d, "%Y-%m")
  } else {
    d <- seq(p$date, by = "3 months", length.out = 2)[2]
    sprintf("%dQ%d", lubridate::year(d), lubridate::quarter(d))
  }
}

#' Lag a period id by n steps of its own frequency.
period_lag <- function(period, n = 1L) {
  p <- parse_period_one(period)
  if (p$freq == "monthly") {
    d <- seq(p$date, by = "-1 month", length.out = n + 1)[n + 1]
    format(d, "%Y-%m")
  } else {
    d <- seq(p$date, by = "-3 months", length.out = n + 1)[n + 1]
    sprintf("%dQ%d", lubridate::year(d), lubridate::quarter(d))
  }
}

#' Human label for a period id ("2026-07" -> "July 2026", "2026Q1" -> "Q1 2026").
period_label <- function(period) {
  p <- parse_period_one(period)
  if (p$freq == "monthly") {
    format(p$date, "%B %Y")
  } else {
    sprintf("Q%d %d", lubridate::quarter(p$date), lubridate::year(p$date))
  }
}

#' South African number formatting for output: decimal comma, thin-space
#' thousands ("4 772 090,6"). Used in prose and tables, not in code.
format_za <- function(x, digits = 1) {
  ifelse(is.na(x), "not available",
         stringr::str_replace(
           formatC(round(x, digits), format = "f", digits = digits, big.mark = " "),
           "\\.", ","))
}
