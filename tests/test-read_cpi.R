# CPI reader tests against the real July 2026 release files cached in
# data-raw/. Known-good values from the brief (verified against Stats SA):
# CPS00000 Jul 2026 index 107.7, y/y 4.3, m/m 0.2; core (CPS00014) y/y 4.2.

cpi_paths <- tryCatch(fetch_release("cpi", "2026-07", root = here::here()),
                      error = function(e) NULL)

test_that("read_cpi_coicop reproduces the July 2026 release values", {
  skip_if(is.null(cpi_paths), "CPI July 2026 files not cached")
  long <- read_cpi_coicop(cpi_paths$coicop, period = "2026-07")

  head_jul <- long$value[long$series_code == "CPS00000" & long$period == "2026-07"]
  expect_equal(head_jul, 107.7)

  # one row per series-period after deduplication
  expect_equal(length(head_jul), 1L)

  yy <- 100 * (107.7 / long$value[long$series_code == "CPS00000" &
                                  long$period == "2025-07"] - 1)
  expect_equal(round(yy, 1), 4.3)

  mm <- 100 * (107.7 / long$value[long$series_code == "CPS00000" &
                                  long$period == "2026-06"] - 1)
  expect_equal(round(mm, 1), 0.2)

  core <- long[long$series_code == "CPS00014", ]
  core_yy <- 100 * (core$value[core$period == "2026-07"] /
                    core$value[core$period == "2025-07"] - 1)
  expect_equal(round(core_yy, 1), 4.2)
})

test_that("read_cpi_coicop enforces the series-code contract", {
  skip_if(is.null(cpi_paths), "CPI July 2026 files not cached")
  long <- read_cpi_coicop(cpi_paths$coicop)
  codes <- series_codes()$cpi
  for (code in c(codes$headline, codes$core, unlist(codes$divisions))) {
    expect_true(code %in% long$series_code, label = paste("series", code, "present"))
  }
  # anchors from the brief
  for (code in c("CPI60001", "CPI60051", "CPI61001", "CPI60065")) {
    expect_true(code %in% long$series_code, label = paste("anchor", code, "present"))
  }
})

test_that("requesting a period beyond the file fails the period assertion", {
  skip_if(is.null(cpi_paths), "CPI July 2026 files not cached")
  expect_error(read_cpi_coicop(cpi_paths$coicop, period = "2027-01"),
               "check_reported_period_matches_requested")
})

test_that("read_cpi_products loads weights that sum to 100 with NA (not zero) gaps", {
  skip_if(is.null(cpi_paths), "CPI files not cached")
  prod <- read_cpi_products(cpi_paths$digit8)
  w <- unique(prod[, c("product_code", "Weight")])
  expect_equal(sum(w$Weight, na.rm = TRUE), 100, tolerance = 1e-6)
  rice <- w$Weight[w$product_code == "01111201"]
  expect_equal(rice, 0.5402427610422024, tolerance = 1e-12)
  # blanks are NA, never zero
  expect_true(anyNA(prod$value))
  expect_false(any(prod$value == 0, na.rm = TRUE))
  # Stats SA's own concordance column is retained
  expect_true("Old code" %in% names(prod))
})

test_that("breadth series reaches the CPI reference month (needs 202607 8-digit vintage)", {
  skip_if(is.null(cpi_paths), "CPI files not cached")
  prod <- read_cpi_products(cpi_paths$digit8)
  # KNOWN GAP: only the 202504 vintage of the 8-digit file was obtainable at
  # build time (see docs/OPEN_QUESTIONS.md). This test names that gap and
  # passes once the current-vintage file is fetched on a trusted network.
  expect_true("2026-07" %in% prod$period,
              label = "8-digit product file extends to July 2026")
})
