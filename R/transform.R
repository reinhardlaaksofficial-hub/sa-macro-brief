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

# ---------------------------------------------------------------------------
# PPI

transform_ppi <- function(d, period, root = here::here()) {
  codes <- series_codes(root)$ppi
  cpi_codes <- series_codes(root)$cpi
  long <- d$ppi

  headline <- list(
    index = series_value(long, codes$headline, period),
    mm = pct_change(long, codes$headline, period, 1),
    yy = pct_change(long, codes$headline, period, 12),
    yy_prior = pct_change(long, codes$headline, period_lag(period, 1), 12),
    cpi_yy = if (!is.null(d$cpi)) pct_change(d$cpi, cpi_codes$headline, period, 12) else NA_real_
  )

  hist_ppi <- yy_history(long, list(PPI = codes$headline), period, years = 5)
  history <- hist_ppi
  if (!is.null(d$cpi)) {
    hist_cpi <- yy_history(d$cpi, list(CPI = cpi_codes$headline), period, years = 5)
    # align CPI overlay to months the PPI series covers
    hist_cpi <- hist_cpi[hist_cpi$date >= min(hist_ppi$date), ]
    history <- rbind(hist_ppi, hist_cpi)
  }

  # m/m over the trailing 24 months for the second chart
  sub <- long[long$series_code == codes$headline & !is.na(long$value), ]
  sub <- sub[order(sub$date), ]
  mm <- data.frame(date = sub$date, period = sub$period,
                   mm = 100 * (sub$value / dplyr::lag(sub$value, 1) - 1))
  p <- parse_period_one(period)
  mm <- mm[!is.na(mm$mm) & mm$date > p$date - lubridate::years(2) & mm$date <= p$date, ]

  vintage_stamp <- tryCatch(d$vintage[[1]]$retrieved_at, error = function(e) NA_character_)
  revisions <- snapshot_and_diff(long, "ppi", c(codes$headline),
                                 vintage_stamp %||% format(Sys.time(), tz = "UTC"),
                                 root = root)

  list(release = "ppi", period = period, label = period_label(period),
       headline = headline, history = history, mm_history = mm,
       revisions = revisions, vintage = d$vintage)
}

# ---------------------------------------------------------------------------
# GDP

transform_gdp <- function(d, period, root = here::here()) {
  codes <- series_codes(root)$gdp
  long <- d$gdp

  headline <- list(
    level = series_value(long, codes$headline_constant_saa, period),
    qq = pct_change(long, codes$headline_constant_saa, period, 1),
    qq_prior = pct_change(long, codes$headline_constant_saa, period_lag(period, 1), 1),
    # y/y on unadjusted constant-price actuals, the release's y/y convention
    yy = pct_change(long, codes$headline_constant_actual, period, 4),
    nominal_level = series_value(long, codes$headline_current_saa, period)
  )

  # q/q sa bars over three years
  sub <- long[long$series_code == codes$headline_constant_saa & !is.na(long$value), ]
  sub <- sub[order(sub$date), ]
  qq <- data.frame(date = sub$date, period = sub$period,
                   qq = 100 * (sub$value / dplyr::lag(sub$value, 1) - 1))
  p <- parse_period_one(period)
  qq_history <- qq[!is.na(qq$qq) & qq$date > p$date - lubridate::years(3) &
                     qq$date <= p$date, ]

  # industry contributions to q/q growth in pp:
  #   pp_i = 100 * (X_i,t - X_i,t-1) / GDP_{t-1}
  # computed on seasonally adjusted annualised constant-price levels; the
  # annualisation scalar cancels in the ratio.
  ind_names <- c(agriculture = "Agriculture", mining = "Mining",
                 manufacturing = "Manufacturing",
                 electricity_gas_water = "Electricity, gas & water",
                 construction = "Construction",
                 trade_catering_accommodation = "Trade & accommodation",
                 transport_communication = "Transport & communication",
                 finance_real_estate_business = "Finance & business services",
                 general_government = "General government",
                 personal_services = "Personal services")
  gdp_prev <- series_value(long, codes$headline_constant_saa, period_lag(period, 1))
  contrib_one <- function(code) {
    100 * (series_value(long, code, period) -
             series_value(long, code, period_lag(period, 1))) / gdp_prev
  }
  contributions <- data.frame(
    key = names(codes$industries_saa),
    name = ind_names[names(codes$industries_saa)],
    code = unlist(codes$industries_saa),
    pp = vapply(codes$industries_saa, contrib_one, 0),
    stringsAsFactors = FALSE
  )
  taxes_pp <- contrib_one(codes$taxes_less_subsidies)
  contributions <- rbind(contributions,
                         data.frame(key = "taxes_less_subsidies",
                                    name = "Taxes less subsidies",
                                    code = codes$taxes_less_subsidies,
                                    pp = taxes_pp))

  # reconciliation: contributions must sum to headline q/q within rounding
  gap <- sum(contributions$pp) - headline$qq
  if (is.na(gap) || abs(gap) > 0.06) {
    stop("check_gdp_contributions_reconcile: contributions sum to ",
         round(sum(contributions$pp), 3), " vs headline q/q ",
         round(headline$qq, 3), call. = FALSE)
  }

  vintage_stamp <- tryCatch(d$vintage[[1]]$retrieved_at, error = function(e) NA_character_)
  revisions <- snapshot_and_diff(long, "gdp",
                                 c(codes$headline_constant_saa, codes$industries_saa),
                                 vintage_stamp %||% format(Sys.time(), tz = "UTC"),
                                 root = root)

  breaks <- yaml::read_yaml(file.path(root, "config", "series_breaks.yaml"))$breaks
  pending <- Filter(function(b) identical(b$kind, "rebase_pending") &&
                      identical(b$release, "gdp"), breaks)
  flags <- if (length(pending) > 0)
    "Note: Stats SA has announced a rebasing of the national accounts to a 2022 base year, pending later in 2026." else character(0)

  revision_history <- gdp_revision_history(root)
  if (nrow(revision_history) > 0) {
    flags <- c(flags, sprintf(
      "Across the %d quarters tracked so far, first-print q/q growth has moved by %s pp on average between vintages (mean absolute revision).",
      nrow(revision_history),
      format_za(mean(abs(revision_history$revision_pp), na.rm = TRUE), 2)))
  }

  list(release = "gdp", period = period, label = period_label(period),
       headline = headline, qq_history = qq_history,
       contributions = contributions, flags = flags,
       revision_history = revision_history,
       revisions = revisions, vintage = d$vintage)
}

# ---------------------------------------------------------------------------
# QLFS

#' Accumulate rate observations across parsed releases so the LU chart's
#' history grows with each cached PDF (LU3 exists only from Q3:2025; a long
#' backrun is structurally unavailable).
qlfs_accumulate_rates <- function(a, periods, root = here::here()) {
  dir.create(file.path(root, "data", "vintages"), recursive = TRUE, showWarnings = FALSE)
  path <- file.path(root, "data", "vintages", "qlfs_rates.csv")
  obs <- list()
  for (k in c("lu1", "lu3", "participation_rate", "absorption_rate")) {
    vals <- as.numeric(a[a$key == k, c("q_yr_ago", "q_prev", "q_now")])
    obs[[k]] <- data.frame(key = k, period = periods, rate = vals)
  }
  cur <- do.call(rbind, obs)
  cur <- cur[!is.na(cur$rate), ]
  if (file.exists(path)) {
    prev <- utils::read.csv(path)
    cur <- rbind(prev, cur)
    cur <- cur[!duplicated(cur[, c("key", "period")]), ]
  }
  cur <- cur[order(cur$key, cur$period), ]
  utils::write.csv(cur, path, row.names = FALSE)
  cur
}

transform_qlfs <- function(d, period, root = here::here()) {
  a <- d$table_a
  g <- function(k, col = "q_now") a[a$key == k, col]

  store <- qlfs_accumulate_rates(a, d$periods, root = root)
  rate_history <- store[store$key %in% c("lu1", "lu3"), ]
  rate_history$series <- toupper(rate_history$key)
  rate_history$date <- parse_period(rate_history$period)$date
  rate_history <- rate_history[!is.na(rate_history$date), ]
  names(rate_history)[names(rate_history) == "rate"] <- "rate"

  industry_changes <- d$table_b[d$table_b$industry != "Total", ]
  industry_changes <- data.frame(name = industry_changes$industry,
                                 change = industry_changes$qq_change,
                                 yy_change = industry_changes$yy_change,
                                 level = industry_changes$q_now,
                                 stringsAsFactors = FALSE)

  # the commentary's first sentence always reports the LU1 pp change, so no
  # separate threshold flag is added for it
  flags <- character(0)

  list(release = "qlfs", period = period, label = period_label(period),
       table_a = a, periods = d$periods,
       rate_history = rate_history, industry_changes = industry_changes,
       flags = flags, revisions = NULL, vintage = d$vintage)
}
