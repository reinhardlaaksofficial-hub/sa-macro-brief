# Fetch layer. Fetches Stats SA artefacts with polite etiquette, caches every
# download to data-raw/ stamped with retrieval time (the vintage), and never
# re-fetches cached content unless refresh = TRUE.
#
# This layer only fetches and caches; it never parses file contents beyond the
# post-download period check delegated to the caller. Filenames are never
# constructed for publication-page artefacts: the page is scraped and links
# are taken verbatim (files get re-versioned as _v2/_v3 after corrections).
#
# Mirror fallback: www.statssa.gov.za sits behind Imperva bot protection that
# challenges non-browser clients on some networks. When the direct fetch is
# blocked, fetch_url() falls back to the Internet Archive's copy of the same
# URL (web.archive.org), and records which source served the bytes in the
# vintage metadata. See docs/OPEN_QUESTIONS.md.

sa_config <- function(root = here::here()) {
  yaml::read_yaml(file.path(root, "config", "sources.yaml"))
}

#' Shared throttle: at least `min_delay` seconds between any two requests to
#' the same host, process-wide.
.fetch_state <- new.env(parent = emptyenv())

throttle <- function(min_delay = 1) {
  last <- .fetch_state$last_request_time
  if (!is.null(last)) {
    elapsed <- as.numeric(Sys.time()) - last
    if (elapsed < min_delay) Sys.sleep(min_delay - elapsed)
  }
  .fetch_state$last_request_time <- as.numeric(Sys.time())
  invisible(NULL)
}

#' Build the polite request object.
sa_request <- function(url, cfg = sa_config()) {
  httr2::request(url) |>
    httr2::req_user_agent(cfg$fetch$user_agent) |>
    httr2::req_timeout(120) |>
    # exponential backoff on transient failures; never parallelised
    httr2::req_retry(
      max_tries = cfg$fetch$max_retries,
      backoff = function(attempt) min(2^attempt, 60)
    )
}

#' Detect the Imperva/Incapsula challenge page (bot protection) so it is
#' reported as "blocked", never mistaken for content.
is_challenge_page <- function(body_bytes) {
  if (length(body_bytes) > 20000L) return(FALSE)
  txt <- rawToChar(body_bytes[seq_len(min(length(body_bytes), 4000L))])
  Encoding(txt) <- "UTF-8"
  grepl("Incapsula|Imperva|_Incapsula_Resource", txt, useBytes = TRUE)
}

#' Wayback fallback URL for a Stats SA URL ("if_" returns the original bytes).
wayback_url <- function(url) {
  paste0("https://web.archive.org/web/2026if_/", url)
}

#' Fetch a URL to a local path. Returns a list(path, source, retrieved_at)
#' or errors. `source` is "statssa" or "wayback".
fetch_url <- function(url, dest, cfg = sa_config()) {
  throttle(cfg$fetch$min_delay_seconds)
  src <- "statssa"
  resp <- tryCatch(
    httr2::req_perform(sa_request(url, cfg)),
    error = function(e) e
  )
  blocked <- inherits(resp, "error") ||
    httr2::resp_status(resp) >= 400 ||
    is_challenge_page(httr2::resp_body_raw(resp))
  if (blocked) {
    message("Direct fetch blocked or failed for ", url, " - trying Internet Archive mirror")
    throttle(cfg$fetch$min_delay_seconds)
    src <- "wayback"
    resp <- httr2::req_perform(sa_request(wayback_url(url), cfg))
    if (httr2::resp_status(resp) >= 400) {
      stop("Fetch failed from both Stats SA and the Internet Archive: ", url, call. = FALSE)
    }
  }
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  writeBin(httr2::resp_body_raw(resp), dest)
  list(path = dest, source = src, retrieved_at = format(Sys.time(), tz = "UTC", usetz = TRUE))
}

#' Cache-aware fetch. Files land in data-raw/{release}/ with a sidecar
#' .vintage.yaml recording url, retrieval time and source. Cached files are
#' never re-fetched unless refresh = TRUE.
fetch_cached <- function(url, release, filename = NULL, refresh = FALSE,
                         root = here::here(), cfg = sa_config()) {
  if (is.null(filename)) filename <- utils::URLdecode(basename(url))
  dest <- file.path(root, "data-raw", release, filename)
  meta_path <- paste0(dest, ".vintage.yaml")
  if (file.exists(dest) && file.exists(meta_path) && !refresh) {
    meta <- yaml::read_yaml(meta_path)
    meta$path <- dest
    meta$from_cache <- TRUE
    return(meta)
  }
  got <- fetch_url(url, dest, cfg)
  meta <- list(url = url, filename = filename, source = got$source,
               retrieved_at = got$retrieved_at,
               size_bytes = file.size(dest))
  yaml::write_yaml(meta, meta_path)
  meta$path <- dest
  meta$from_cache <- FALSE
  meta
}

#' Scrape a publication page and return a data.frame of artefact links:
#' label, href (absolute), filename. Never constructs filenames.
scrape_publication_page <- function(ppn, sch, refresh = FALSE,
                                    root = here::here(), cfg = sa_config()) {
  url <- sub("\\{PPN\\}", ppn, cfg$publication_page)
  url <- sub("\\{SCH\\}", sch, url)
  cache_name <- sprintf("pubpage_%s_%s.html", gsub("[^A-Za-z0-9.]", "_", ppn), sch)
  meta <- fetch_cached(url, "pubpages", cache_name, refresh = refresh, root = root, cfg = cfg)
  html <- rvest::read_html(meta$path)
  a <- rvest::html_elements(html, "a")
  href <- rvest::html_attr(a, "href")
  label <- stringr::str_squish(rvest::html_text2(a))
  keep <- !is.na(href) & stringr::str_detect(href, "(?i)\\.(xlsx?|zip|pdf)($|\\?)")
  href <- href[keep]; label <- label[keep]
  href <- ifelse(stringr::str_detect(href, "^https?://"),
                 href, paste0(cfg$base_url, "/", sub("^/", "", href)))
  data.frame(label = label, href = href,
             filename = utils::URLdecode(basename(sub("\\?.*$", "", href))),
             stringsAsFactors = FALSE)
}

#' Extract "Publication date & time: 22 July 2026 @ 10:00" from a publication
#' page. Returns POSIXct (SAST) or NA if absent.
extract_publication_datetime <- function(html_path) {
  txt <- rvest::html_text2(rvest::read_html(html_path))
  m <- stringr::str_match(
    txt, "Publication date\\s*&\\s*time:\\s*(\\d{1,2} \\w+ \\d{4})\\s*@\\s*(\\d{1,2}:\\d{2})")
  if (is.na(m[1, 1])) return(as.POSIXct(NA))
  lubridate::dmy_hm(paste(m[1, 2], m[1, 3]), tz = "Africa/Johannesburg")
}

#' Flag re-versioned artefacts: a _v2 is expected after corrections; a _v3
#' (or higher) is a revision signal worth surfacing, not an error.
flag_reversions <- function(links) {
  v <- stringr::str_match(links$filename, "_v(\\d+)\\.")[, 2]
  v <- suppressWarnings(as.integer(v))
  if (any(!is.na(v) & v >= 3)) {
    message("Revision signal: artefact(s) at version >= 3: ",
            paste(links$filename[!is.na(v) & v >= 3], collapse = ", "))
  }
  invisible(links)
}

#' Discover the SCH id of the latest release of a publication from the
#' publications index. SCH is a per-release schedule id (each release of a
#' publication gets its own SCH), so it must be discovered, not configured.
discover_sch <- function(ppn, refresh = FALSE, root = here::here(), cfg = sa_config()) {
  # The site search page lists releases with page_id=1854&PPN=..&SCH=.. links.
  url <- paste0(cfg$base_url, "/?page_id=1854&PPN=", utils::URLencode(ppn, reserved = TRUE))
  cache_name <- sprintf("index_%s.html", gsub("[^A-Za-z0-9.]", "_", ppn))
  meta <- fetch_cached(url, "pubpages", cache_name, refresh = refresh, root = root, cfg = cfg)
  html <- rvest::read_html(meta$path)
  href <- rvest::html_attr(rvest::html_elements(html, "a"), "href")
  sch <- stringr::str_match(href, "SCH=(\\d+)")[, 2]
  sch <- sch[!is.na(sch)]
  if (length(sch) == 0) {
    stop("Could not discover an SCH id for ", ppn, " from ", url, call. = FALSE)
  }
  # Highest SCH observed = latest scheduled release.
  as.character(max(as.integer(sch)))
}

#' Cache-first artefact lookup: newest file in data-raw/{release}/ whose name
#' matches `pattern` (regex) and, when given, contains the vintage tag
#' `period_tag` (e.g. "202607" or "Q1 2026"). Returns a path or NA.
find_cached_artifact <- function(release, pattern, period_tag = NULL, root = here::here()) {
  dir <- file.path(root, "data-raw", release)
  if (!dir.exists(dir)) return(NA_character_)
  files <- list.files(dir, full.names = TRUE)
  files <- files[!grepl("\\.vintage\\.yaml$", files)]
  files <- files[grepl(pattern, basename(files))]
  if (!is.null(period_tag)) files <- files[grepl(period_tag, basename(files), fixed = TRUE)]
  files <- files[!file.info(files)$isdir]
  if (length(files) == 0) return(NA_character_)
  files[order(file.info(files)$mtime, decreasing = TRUE)][1]
}

#' Fetch the artefacts needed for one release. Cache-first: if a matching
#' artefact for the requested period is already in data-raw/, it is used
#' without touching the network (unless refresh = TRUE). Otherwise the
#' publication page is scraped and the matching links fetched.
#'
#' `period_tag` per release: CPI/PPI "YYYYMM" vintage in zip names;
#' GDP "Qn YYYY" in the xlsx name; QLFS "{N}{st|nd|rd|th}Quarter{YYYY}".
#' Returns a named list of local paths plus the vintage metadata.
fetch_release <- function(release, period, refresh = FALSE,
                          root = here::here(), cfg = sa_config()) {
  p <- parse_period_one(period)
  patterns <- switch(release,
    cpi = list(
      coicop = "CPI\\(COICOP\\) from Jan 2008.*\\.zip$",
      digit8 = "CPI\\(5 and 8 digit\\) from Jan 2017.*\\.zip$"),
    ppi = list(main = "PPI New series from 2013.*\\.zip$"),
    gdp = list(main = "GDP Time series.*\\.xlsx$"),
    qlfs = list(main = "^P0211.*Quarter\\d{4}\\.pdf$"),
    stop("Unknown release: ", release, call. = FALSE)
  )
  tag <- switch(release,
    cpi = , ppi = gsub("-", "", p$period),
    gdp = sprintf("Q%d %d", lubridate::quarter(p$date), lubridate::year(p$date)),
    qlfs = {
      q <- lubridate::quarter(p$date)
      sprintf("%d%sQuarter%d", q, c("st", "nd", "rd", "th")[q], lubridate::year(p$date))
    })

  out <- list()
  missing <- character(0)
  for (nm in names(patterns)) {
    hit <- if (refresh) NA_character_ else
      find_cached_artifact(release, patterns[[nm]], tag, root)
    # CPI 8-digit fallback: weights are static within a basket year, so an
    # earlier vintage is acceptable for weights (recorded by the caller).
    if (is.na(hit) && release == "cpi" && nm == "digit8" && !refresh) {
      hit <- find_cached_artifact(release, patterns[[nm]], NULL, root)
    }
    if (!is.na(hit)) out[[nm]] <- hit else missing <- c(missing, nm)
  }
  if (length(missing) > 0) {
    rel_cfg <- cfg$releases[[release]]
    sch <- rel_cfg$sch %||% discover_sch(rel_cfg$ppn, refresh = refresh, root = root, cfg = cfg)
    links <- scrape_publication_page(rel_cfg$ppn, sch, refresh = refresh, root = root, cfg = cfg)
    flag_reversions(links)
    for (nm in missing) {
      match_i <- grepl(patterns[[nm]], links$filename)
      if (!any(match_i)) {
        stop(sprintf("No artefact matching '%s' on publication page for %s (%s). Links seen: %s",
                     patterns[[nm]], release, sch,
                     paste(utils::head(links$filename, 10), collapse = "; ")), call. = FALSE)
      }
      link <- links[match_i, ][1, ]
      meta <- fetch_cached(link$href, release, link$filename, refresh = refresh, root = root, cfg = cfg)
      out[[nm]] <- meta$path
    }
  }
  # unzip any zips, returning the contained spreadsheet path
  for (nm in names(out)) {
    if (grepl("\\.zip$", out[[nm]], ignore.case = TRUE)) {
      extracted <- unzip_cached(out[[nm]])
      xlsx <- extracted[grepl("\\.xlsx?$", extracted, ignore.case = TRUE)]
      if (length(xlsx) == 0) stop("Zip contained no spreadsheet: ", out[[nm]], call. = FALSE)
      out[[nm]] <- xlsx[1]
    }
  }
  out$vintage <- read_vintage(out, release, root)
  out
}

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

#' Collect vintage metadata for fetched artefact paths (sidecar files written
#' by fetch_cached; seeded caches carry them too).
read_vintage <- function(paths, release, root = here::here()) {
  paths <- unlist(paths[names(paths) != "vintage"])
  metas <- list()
  for (p in paths) {
    # the sidecar sits next to the original artefact (zip, not extracted file)
    candidates <- c(paste0(p, ".vintage.yaml"),
                    paste0(dirname(p), ".zip.vintage.yaml"))
    m <- candidates[file.exists(candidates)][1]
    if (!is.na(m)) metas[[basename(p)]] <- yaml::read_yaml(m)
  }
  metas
}

#' Unzip a cached zip into a sibling directory; returns extracted paths.
unzip_cached <- function(zip_path) {
  exdir <- sub("\\.zip$", "", zip_path, ignore.case = TRUE)
  dir.create(exdir, recursive = TRUE, showWarnings = FALSE)
  files <- zip::zip_list(zip_path)$filename
  zip::unzip(zip_path, exdir = exdir)
  file.path(exdir, files)
}
