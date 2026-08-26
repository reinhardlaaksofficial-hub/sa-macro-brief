# QLFS parser tests against the cached Q2 2026 PDF.
# Known-good values from the brief: LU1 33,6; LU3 43,8; absorption 39,6;
# participation 59,6; employed 16 739 thousand.

qlfs <- tryCatch(suppressWarnings(load_qlfs("2026Q2", root = here::here())),
                 error = function(e) NULL)

test_that("Table A reproduces the Q2 2026 release values", {
  skip_if(is.null(qlfs), "QLFS Q2 2026 PDF not cached")
  a <- qlfs$table_a
  g <- function(k, col = "q_now") a[a$key == k, col]
  expect_equal(g("lu1"), 33.6)
  expect_equal(g("lu3"), 43.8)
  expect_equal(g("absorption_rate"), 39.6)
  expect_equal(g("participation_rate"), 59.6)
  expect_equal(g("employed"), 16739)
  expect_equal(g("population_15_64"), 42310)
  expect_equal(attr(a, "periods"), c("2025Q2", "2026Q1", "2026Q2"))
})

test_that("space-thousands and decimal commas parse; rate changes are pp", {
  skip_if(is.null(qlfs), "QLFS Q2 2026 PDF not cached")
  a <- qlfs$table_a
  g <- function(k, col = "q_now") a[a$key == k, col]
  expect_equal(g("population_15_64", "q_yr_ago"), 41822)  # "41 822"
  # rates carry pp changes, never per cent changes
  expect_equal(g("lu1", "qq_pp"), 0.9)
  expect_true(is.na(g("lu1", "qq_pct")))
})

test_that("informality rows carry no pre-break comparisons (Q3:2025 break)", {
  skip_if(is.null(qlfs), "QLFS Q2 2026 PDF not cached")
  a <- qlfs$table_a
  for (k in c("formal_sector", "informal_sector")) {
    expect_true(is.na(a[a$key == k, "q_yr_ago"]), label = paste(k, "year-ago NA"))
    expect_true(is.na(a[a$key == k, "yy_change"]), label = paste(k, "y/y NA"))
    expect_false(is.na(a[a$key == k, "q_now"]), label = paste(k, "current present"))
  }
})

test_that("accounting identities hold", {
  skip_if(is.null(qlfs), "QLFS Q2 2026 PDF not cached")
  expect_silent(assert_qlfs_identities(qlfs$table_a))
})

test_that("Table B industries parse with Total matching Table A employed", {
  skip_if(is.null(qlfs), "QLFS Q2 2026 PDF not cached")
  b <- qlfs$table_b
  expect_equal(nrow(b), 11L)
  expect_equal(b$q_now[b$industry == "Total"],
               qlfs$table_a[qlfs$table_a$key == "employed", "q_now"])
  expect_equal(b$qq_change[b$industry == "Trade"], 70)
})

test_that("requesting the wrong quarter fails the cover-period assertion", {
  skip_if(is.null(qlfs), "QLFS Q2 2026 PDF not cached")
  paths <- fetch_release("qlfs", "2026Q2", root = here::here())
  txt <- pdftools::pdf_text(paths$main)
  expect_error(assert_qlfs_cover(txt, "2026Q1"),
               "check_reported_period_matches_requested")
  expect_true(assert_qlfs_cover(txt, "2026Q2"))
})
