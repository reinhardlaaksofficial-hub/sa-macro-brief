# Release watcher: the scheduled entry point.
#
# Stats SA's publication dates move within the month (CPI is "a Wednesday in
# the third or fourth week"), and the advance schedule lives on the HTML
# pages, which are not always reachable. So the watcher does not run off a
# calendar at all. It asks the only question that matters:
#
#     is there a completed reference period whose brief I have not built yet,
#     and is its file on the server now?
#
# That is robust to schedule drift, needs no knowledge of release dates, and
# is idempotent: once a brief exists for a period, the watcher leaves it
# alone, so it can be run as often as politeness allows.

#' The most recently completed reference periods, newest first.
#' A period is a candidate only once it has ended - Stats SA cannot publish
#' July CPI before July is over.
recent_periods <- function(freq, n = 3, now = Sys.Date()) {
  if (freq == "monthly") {
    first_of_this_month <- as.Date(format(now, "%Y-%m-01"))
    starts <- seq(first_of_this_month, by = "-1 month", length.out = n + 1)[-1]
    format(starts, "%Y-%m")
  } else {
    q_start <- as.Date(sprintf("%d-%02d-01", lubridate::year(now),
                               (lubridate::quarter(now) - 1L) * 3L + 1L))
    starts <- seq(q_start, by = "-3 months", length.out = n + 1)[-1]
    sprintf("%dQ%d", lubridate::year(starts), lubridate::quarter(starts))
  }
}

#' Has a brief already been produced for this release and period?
brief_exists <- function(release, period, root = here::here()) {
  file.exists(file.path(root, "output",
                        sprintf("%s_%s.pdf", release,
                                gsub("[^A-Za-z0-9]", "", period))))
}

#' Build one brief end to end. Returns the PDF path.
build_brief <- function(release, period, root = here::here(), wait = 0) {
  payload <- switch(release,
    cpi = {
      d <- load_cpi(period, root = root, wait = wait)
      payload_cpi(add_cpi_analytics(transform_cpi(d, period, root = root), d, root = root),
                  root = root)
    },
    ppi = {
      d <- load_ppi(period, root = root, wait = wait)
      payload_ppi(transform_ppi(d, period, root = root), root = root)
    },
    gdp = {
      d <- load_gdp(period, root = root, wait = wait)
      payload_gdp(transform_gdp(d, period, root = root), root = root)
    },
    qlfs = {
      d <- load_qlfs(period, root = root, wait = wait)
      payload_qlfs(transform_qlfs(d, period, root = root), root = root)
    },
    stop("Unknown release: ", release, call. = FALSE)
  )
  render_brief(payload, root = root)
}

#' Is the release's primary artefact on the server for this period?
#' A cheap HEAD probe, no download, no waiting.
release_available <- function(release, period, root = here::here(),
                              cfg = sa_config(root)) {
  key <- if (release %in% c("cpi")) "coicop" else "main"
  hit <- tryCatch(discover_by_probe(release, period, key, cfg, wait_minutes = 0),
                  error = function(e) NULL)
  !is.null(hit)
}

#' One watch pass. For each release, find the newest completed period that has
#' no brief yet, and build it if the data is up. Never builds more than one
#' period per release per pass; never re-builds what exists.
#'
#' Returns a data.frame of outcomes: release, period, status, detail.
watch_once <- function(releases = c("cpi", "ppi", "gdp", "qlfs"),
                       root = here::here(), dry_run = FALSE,
                       lookback = 3, now = Sys.Date(), backfill = FALSE,
                       cfg = sa_config(root)) {
  # cfg stays a lazy argument: a pass where every release is already up to
  # date never probes, so it never needs to read configuration at all.
  freqs <- c(cpi = "monthly", ppi = "monthly", gdp = "quarterly", qlfs = "quarterly")
  out <- list()

  for (release in releases) {
    periods <- recent_periods(freqs[[release]], lookback, now)
    pending <- periods[!vapply(periods, function(p) brief_exists(release, p, root), TRUE)]

    # New information means the newest completed period. If that one is
    # already built there is nothing new, even when older gaps exist: filling
    # those is a deliberate --backfill choice, not something a scheduled run
    # should do on its own.
    if (!backfill) {
      pending <- if (brief_exists(release, periods[1], root)) character(0) else periods[1]
    }

    if (length(pending) == 0) {
      out[[release]] <- data.frame(release = release, period = periods[1],
                                   status = "up_to_date",
                                   detail = "newest period already built")
      next
    }

    built <- FALSE
    for (period in pending) {
      if (!release_available(release, period, root, cfg)) next
      if (dry_run) {
        out[[release]] <- data.frame(release = release, period = period,
                                     status = "would_build",
                                     detail = "data is on the server")
        built <- TRUE
        break
      }
      res <- tryCatch({
        path <- build_brief(release, period, root = root)
        data.frame(release = release, period = period, status = "built",
                   detail = basename(path))
      }, error = function(e) {
        # one release failing must not stop the others
        data.frame(release = release, period = period, status = "failed",
                   detail = conditionMessage(e))
      })
      out[[release]] <- res
      built <- TRUE
      break
    }
    if (!built) {
      out[[release]] <- data.frame(release = release, period = pending[1],
                                   status = "not_published_yet",
                                   detail = "no artefact on the server yet")
    }
  }
  do.call(rbind, out)
}

#' Scheduled entry point: run a pass, log it, and notify on anything new.
watch_run <- function(releases = c("cpi", "ppi", "gdp", "qlfs"),
                      root = here::here(), dry_run = FALSE, backfill = FALSE) {
  results <- watch_once(releases, root = root, dry_run = dry_run,
                        backfill = backfill)
  stamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
  log_dir <- file.path(root, "output", "logs")
  dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
  line <- sprintf("%s  %s %s %s  %s", stamp, results$release, results$period,
                  results$status, results$detail)
  cat(line, sep = "\n")
  cat(line, sep = "\n", file = file.path(log_dir, "watch.log"), append = TRUE)

  fresh <- results[results$status == "built", ]
  if (nrow(fresh) > 0 && !dry_run) {
    for (i in seq_len(nrow(fresh))) {
      notify_brief(fresh$release[i], fresh$period[i],
                   file.path(root, "output", fresh$detail[i]), root = root)
    }
  }
  invisible(results)
}
