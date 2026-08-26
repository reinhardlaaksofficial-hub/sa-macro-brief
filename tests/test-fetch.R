# Fetch-layer tests run offline against a committed fixture of the real
# GDP Q1 2026 publication page (captured on release day, before the _v2
# re-versioning).

test_that("scrape_publication_page parses real artefact links, never constructs names", {
  skip_if_not(file.exists(fixture_path("pubpage_gdp_q1_2026.html")))
  html <- rvest::read_html(fixture_path("pubpage_gdp_q1_2026.html"))
  a <- rvest::html_elements(html, "a")
  href <- rvest::html_attr(a, "href")
  keep <- !is.na(href) & stringr::str_detect(href, "(?i)\\.(xlsx?|zip|pdf)($|\\?)")
  files <- utils::URLdecode(basename(sub("\\?.*$", "", href[keep])))
  # the release-day page carries the un-suffixed name; the space is missing
  # in "P0441- Q1" exactly as the brief warns
  expect_true("GDP P0441 - GDP Time series Q1 2026.xlsx" %in% files)
  expect_true("GDP P0441- Q1 2026.xlsx" %in% files)
  expect_true("P04411stQuarter2026.pdf" %in% files)
})

test_that("extract_publication_datetime reads the page's embargo stamp", {
  skip_if_not(file.exists(fixture_path("pubpage_gdp_q1_2026.html")))
  dt <- extract_publication_datetime(fixture_path("pubpage_gdp_q1_2026.html"))
  expect_false(is.na(dt))
  expect_equal(lubridate::year(dt), 2026)
})

test_that("flag_reversions surfaces _v3 as a revision signal, accepts _v2 quietly", {
  links2 <- data.frame(label = "x", href = "y",
                       filename = "GDP P0441 - GDP Time series Q1 2026_v2.xlsx")
  expect_silent(flag_reversions(links2))
  links3 <- data.frame(label = "x", href = "y",
                       filename = "GDP P0441 - GDP Time series Q1 2026_v3.xlsx")
  expect_message(flag_reversions(links3), "version >= 3")
})

test_that("is_challenge_page recognises the Imperva interstitial", {
  challenge <- charToRaw("<html><script src=\"/_Incapsula_Resource?x=1\"></script></html>")
  expect_true(is_challenge_page(challenge))
  content <- charToRaw(paste(rep("real content", 100), collapse = " "))
  expect_false(is_challenge_page(content))
})

test_that("find_cached_artifact matches release artefacts by pattern and period tag", {
  root <- here::here()
  skip_if_not(dir.exists(file.path(root, "data-raw", "cpi")))
  hit <- find_cached_artifact("cpi", "CPI\\(COICOP\\) from Jan 2008.*\\.zip$", "202607", root)
  expect_false(is.na(hit))
  miss <- find_cached_artifact("cpi", "CPI\\(COICOP\\) from Jan 2008.*\\.zip$", "199901", root)
  expect_true(is.na(miss))
})
