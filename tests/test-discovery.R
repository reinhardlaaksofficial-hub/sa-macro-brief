# Artefact discovery. The pure-logic parts run offline; the probe test is
# skipped when the live site is unreachable so the suite stays runnable
# without a network.

test_that("candidate_paths covers the observed Stats SA naming variants", {
  cpi <- candidate_paths("cpi", "2026-07", "coicop")
  expect_true(any(grepl("P0141 - CPI(COICOP) from Jan 2008 (202607).zip", cpi, fixed = TRUE)))

  # PPI genuinely has no space before the parenthesis in Stats SA's own links
  ppi <- candidate_paths("ppi", "2026-06", "main")
  expect_true(any(grepl("from 2013(202606).zip", ppi, fixed = TRUE)))

  # GDP: quarter-first and year-first orderings both occur, and the missing
  # space after the publication code is a real observed variant
  gdp <- candidate_paths("gdp", "2026Q1", "main")
  expect_true(any(grepl("GDP Time series Q1 2026", gdp, fixed = TRUE)))
  expect_true(any(grepl("GDP Time series 2026 Q1", gdp, fixed = TRUE)))

  qlfs <- candidate_paths("qlfs", "2026Q2", "main")
  expect_true(any(grepl("P02112ndQuarter2026.pdf", qlfs, fixed = TRUE)))
  q3 <- candidate_paths("qlfs", "2026Q3", "main")
  expect_true(any(grepl("P02113rdQuarter2026.pdf", q3, fixed = TRUE)))
})

test_that("corrected versions are probed before the un-suffixed name", {
  gdp <- candidate_paths("gdp", "2026Q1", "main")
  first_v2 <- min(which(grepl("_v2", gdp)))
  first_plain <- min(which(!grepl("_v\\d", gdp)))
  expect_lt(first_v2, first_plain)
  # and a higher correction outranks _v2
  expect_lt(min(which(grepl("_v3", gdp))), first_v2)
})

test_that("the CPI release PDF carrying Table C is a discoverable artefact", {
  pdfs <- candidate_paths("cpi", "2026-07", "release_pdf")
  expect_true(any(grepl("P0141July2026.pdf", pdfs, fixed = TRUE)))
  expect_true(all(grepl("\\.pdf$", pdfs)))
})

test_that("an unknown artefact key fails loudly rather than guessing", {
  expect_error(candidate_paths("cpi", "2026-07", "nonsense"),
               "No candidate naming pattern")
})

test_that("a cached mirror copy is never reused for discovery pages", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "data-raw", "pubpages"), recursive = TRUE)
  dest <- file.path(root, "data-raw", "pubpages", "stale.html")
  writeLines("<html><a href='/old (202601).zip'>stale</a></html>", dest)
  yaml::write_yaml(list(url = "u", filename = "stale.html", source = "wayback",
                        retrieved_at = "2026-01-01 00:00:00 UTC", size_bytes = 1),
                   paste0(dest, ".vintage.yaml"))
  # allow_mirror = TRUE: a mirrored artefact may be reused
  reused <- fetch_cached("u", "pubpages", "stale.html", root = root,
                         allow_mirror = TRUE)
  expect_true(reused$from_cache)
  # allow_mirror = FALSE (discovery): the stale mirror must be rejected, so
  # the call proceeds to the network and fails on the unusable test URL
  expect_error(fetch_cached("u", "pubpages", "stale.html", root = root,
                            allow_mirror = FALSE))
})

test_that("probe discovery resolves the live GDP artefact to its _v2 correction", {
  hit <- tryCatch(discover_by_probe("gdp", "2026Q1", "main"),
                  error = function(e) NULL)
  skip_if(is.null(hit), "statssa.gov.za not reachable from this network")
  expect_match(hit$filename, "_v2\\.xlsx$")
  expect_equal(hit$version, 2L)
})

test_that("embargo waiting applies to a period due now, not to a back-run", {
  # CPI July 2026 was published in August 2026: current as at 26 Aug 2026
  expect_true(period_is_current("2026-07", as.Date("2026-08-26")))
  # GDP Q1 2026 was published 9 June 2026, ~70 days after quarter end
  expect_true(period_is_current("2026Q1", as.Date("2026-06-09")))
  # an old period is a back-run: a 404 means "never existed", so fail fast
  expect_false(period_is_current("2019-03", as.Date("2026-08-26")))
  # a period that has barely started is not yet publishable
  expect_false(period_is_current("2027-06", as.Date("2026-08-26")))
})

test_that("the embargo retry loop backs off and gives up at its deadline", {
  hit <- tryCatch(discover_by_probe("cpi", "2026-08", "coicop", wait_minutes = 0),
                  error = function(e) NULL)
  skip_if(!is.null(hit), "August 2026 CPI has since been published")
  t0 <- Sys.time()
  expect_message(
    res <- discover_by_probe("cpi", "2026-08", "coicop", wait_minutes = 0.15),
    "not on the server yet")
  expect_null(res)
  # it actually waited rather than returning instantly
  expect_gt(as.numeric(difftime(Sys.time(), t0, units = "secs")), 4)
})
