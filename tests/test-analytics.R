# Analytics: breadth, contributions with reconciliation, revision tracking.

cpi_data <- fx_cpi_data()

test_that("inflation breadth is a plausible monthly share of measurable weight", {
  b <- compute_breadth(cpi_data$products)
  expect_true(all(b$share >= 0 & b$share <= 100))
  # y/y needs 12 months of history: series starts Jan 2009
  expect_equal(min(b$period), "2025-01")  # fixture history starts 2024-01
  # products new to the Jan 2025 basket lack the 12-month history a y/y
  # needs, so measurable weight coverage sits below 100 after the reweight
  # (87,8% in April 2025) and never exceeds it
  expect_gt(utils::tail(b$coverage, 1), 75)
  expect_lte(max(b$coverage), 100 + 1e-9)
  # months are unique and ordered
  expect_false(any(duplicated(b$period)))
})

test_that("division contributions reconcile to headline y/y within tolerance", {
  contrib <- compute_cpi_contributions(cpi_data$coicop, cpi_data$products, "2026-07", root = proj_root)
  expect_equal(nrow(contrib), 13L)
  expect_lt(abs(attr(contrib, "gap")), 0.15)
  # weights are the division sums of product weights, summing to ~100
  expect_equal(sum(contrib$weight), 100, tolerance = 0.01)
})

test_that("computed contributions match the release PDF's Table C", {
  contrib <- compute_cpi_contributions(cpi_data$coicop, cpi_data$products, "2026-07", root = proj_root)
  rc <- reconcile_contributions_text(contrib, fx_tablec_text())
  # Table C folds small divisions into a residual; the ones it publishes
  # must agree with the computed figures to within publication rounding
  published <- rc[!is.na(rc$published), ]
  expect_gte(nrow(published), 10)
  expect_true(all(abs(published$diff) <= 0.1))
  # spot-check against the printed July 2026 values
  expect_equal(published$published[published$key == "housing_utilities"], 1.3)
  expect_equal(published$published[published$key == "transport"], 1.2)
})

test_that("gdp_revision_history is empty with fewer than two vintages", {
  h <- gdp_revision_history(root = proj_root)
  expect_true(is.data.frame(h))
  # columns are stable regardless of store contents
  expect_true(all(c("period", "first_print", "latest", "revision_pp") %in%
                  c(names(h), names(h))))
})

test_that("gdp_revision_history computes first-print movement across vintages", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "data", "vintages"), recursive = TRUE)
  dir.create(file.path(root, "config"))
  file.copy(file.path(proj_root, "config", "series_codes.yaml"),
            file.path(root, "config", "series_codes.yaml"))
  store <- rbind(
    data.frame(series_code = "QRS1000", period = c("2025Q4", "2026Q1"),
               value = c(1000, 1005), vintage = "v1"),
    data.frame(series_code = "QRS1000", period = c("2025Q4", "2026Q1"),
               value = c(1000, 1007), vintage = "v2")
  )
  utils::write.csv(store, file.path(root, "data", "vintages", "gdp.csv"),
                   row.names = FALSE)
  h <- gdp_revision_history(root = root)
  expect_equal(nrow(h), 1L)
  expect_equal(h$first_print, 0.5)
  expect_equal(h$latest, 0.7)
  expect_equal(h$revision_pp, 0.2, tolerance = 1e-9)
})
