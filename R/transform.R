# Transformations: growth rates, briefing aggregates, revision flagging.
# This layer knows nothing about charts or PDF layout.
#
# Definitions enforced here (one symbol, one meaning, everywhere):
#   m/m  month vs preceding month, per cent
#   q/q  quarter vs preceding quarter, seasonally adjusted, per cent, NOT annualised
#   y/y  vs same period one year earlier, per cent
#   pp   percentage points: changes in a rate, and contributions to growth

#' Value of one series at one period (NA if absent — never fabricated).
series_value <- function(long, code, period) {
  v <- long$value[long$series_code == code & long$period == period]
  if (length(v) == 0) NA_real_ else v[1]
}

#' Percentage change of a series between period and its lag of n steps.
pct_change <- function(long, code, period, n_lag) {
  now <- series_value(long, code, period)
  then <- series_value(long, code, period_lag(period, n_lag))
  if (is.na(now) || is.na(then)) return(NA_real_)
  100 * (now / then - 1)
}

#' y/y history of one or more series over the trailing `years`, for charts.
#' Returns date, series (names of `codes`), yy.
yy_history <- function(long, codes, end_period, years = 5) {
  p <- parse_period_one(end_period)
  steps <- if (p$freq == "monthly") 12L else 4L
  rows <- list()
  for (nm in names(codes)) {
    sub <- long[long$series_code == codes[[nm]] & !is.na(long$value), ]
    sub <- sub[order(sub$date), ]
    yy <- 100 * (sub$value / dplyr::lag(sub$value, steps) - 1)
    rows[[nm]] <- data.frame(date = sub$date, series = nm, yy = yy,
                             period = sub$period, stringsAsFactors = FALSE)
  }
  out <- do.call(rbind, rows)
  out <- out[!is.na(out$yy) & out$date >= p$date - lubridate::years(years), ]
  rownames(out) <- NULL
  out
}

#' Snapshot the current values of key series and diff against the previous
#' snapshot: every observation carries a vintage, and when a new release
#' changes a historical value the change is flagged, never silently absorbed.
#' Snapshots accumulate in data/vintages/{release}.csv.
snapshot_and_diff <- function(long, release, codes, vintage_stamp,
                              root = here::here()) {
  dir.create(file.path(root, "data", "vintages"), recursive = TRUE, showWarnings = FALSE)
  path <- file.path(root, "data", "vintages", paste0(release, ".csv"))
  current <- long[long$series_code %in% unlist(codes) & !is.na(long$value),
                  c("series_code", "period", "value")]
  current$vintage <- vintage_stamp

  revisions <- data.frame(series_code = character(0), period = character(0),
                          old = numeric(0), new = numeric(0),
                          old_vintage = character(0))
  if (file.exists(path)) {
    prev <- utils::read.csv(path, colClasses = c(value = "numeric"))
    latest_prev <- prev[!duplicated(prev[, c("series_code", "period")],
                                    fromLast = TRUE), ]
    m <- merge(current, latest_prev, by = c("series_code", "period"),
               suffixes = c("_new", "_old"))
    changed <- m[abs(m$value_new - m$value_old) > 1e-6, ]
    if (nrow(changed) > 0) {
      revisions <- data.frame(series_code = changed$series_code,
                              period = changed$period,
                              old = changed$value_old, new = changed$value_new,
                              old_vintage = changed$vintage_old)
    }
    # append only observations that are new or changed (keeps the store small
    # while preserving every distinct vintage of every observation)
    new_keys <- !paste(current$series_code, current$period, current$value) %in%
      paste(prev$series_code, prev$period, prev$value)
    if (any(new_keys)) {
      utils::write.csv(rbind(prev, current[new_keys, ]), path, row.names = FALSE)
    }
  } else {
    utils::write.csv(current, path, row.names = FALSE)
  }
  revisions
}

#' Analytics beyond arithmetic (breadth, contributions with reconciliation)
#' are attached by add_cpi_analytics() in R/analytics.R; this placeholder is
#' replaced when that module loads after this file (alphabetical sourcing
#' means analytics.R defines the real one first — keep this a fallback).
if (!exists("add_cpi_analytics")) {
  add_cpi_analytics <- function(t, cpi, root = here::here()) t
}

#' CPI briefing aggregates for one period.
transform_cpi <- function(cpi, period, root = here::here()) {
  codes <- series_codes(root)$cpi
  long <- cpi$coicop
  policy <- yaml::read_yaml(file.path(root, "config", "policy.yaml"))$inflation_target

  headline <- list(
    index = series_value(long, codes$headline, period),
    mm = pct_change(long, codes$headline, period, 1),
    yy = pct_change(long, codes$headline, period, 12),
    yy_prior = pct_change(long, codes$headline, period_lag(period, 1), 12),
    core_yy = pct_change(long, codes$core, period, 12),
    core_yy_prior = pct_change(long, codes$core, period_lag(period, 1), 12)
  )

  div_names <- c(food_nab = "Food & non-alcoholic beverages",
                 alcohol_tobacco = "Alcoholic beverages & tobacco",
                 clothing_footwear = "Clothing & footwear",
                 housing_utilities = "Housing & utilities",
                 furnishings = "Furnishings & household equipment",
                 health = "Health",
                 transport = "Transport",
                 information_communication = "Information & communication",
                 recreation_culture = "Recreation, sport & culture",
                 education = "Education services",
                 restaurants_accommodation = "Restaurants & accommodation",
                 insurance_financial = "Insurance & financial services",
                 personal_care_misc = "Personal care & misc. services")
  divisions <- data.frame(
    key = names(codes$divisions),
    code = unlist(codes$divisions),
    name = div_names[names(codes$divisions)],
    yy = vapply(codes$divisions, function(cd) pct_change(long, cd, period, 12), 0),
    stringsAsFactors = FALSE
  )
  divisions <- divisions[order(divisions$yy, decreasing = TRUE), ]

  history <- yy_history(long, list(Headline = codes$headline, Core = codes$core),
                        period, years = 5)

  flags <- character(0)
  if (!is.na(headline$yy)) {
    if (headline$yy > policy$upper)
      flags <- c(flags, sprintf("Headline inflation is above the 3-6%% target band (%.1f%%).", headline$yy))
    if (headline$yy < policy$lower)
      flags <- c(flags, sprintf("Headline inflation is below the 3-6%% target band (%.1f%%).", headline$yy))
    crossed_in <- !is.na(headline$yy_prior) &&
      (headline$yy_prior > policy$upper | headline$yy_prior < policy$lower) &&
      headline$yy <= policy$upper & headline$yy >= policy$lower
    if (isTRUE(crossed_in)) flags <- c(flags, "Headline inflation re-entered the target band.")
  }

  vintage_stamp <- tryCatch(cpi$vintage[[1]]$retrieved_at, error = function(e) NA_character_)
  revisions <- snapshot_and_diff(long, "cpi",
                                 c(codes$headline, codes$core, codes$divisions),
                                 vintage_stamp %||% format(Sys.time(), tz = "UTC"),
                                 root = root)

  list(release = "cpi", period = period, label = period_label(period),
       headline = headline, divisions = divisions, history = history,
       policy = policy, flags = flags, revisions = revisions,
       vintage = cpi$vintage)
}
