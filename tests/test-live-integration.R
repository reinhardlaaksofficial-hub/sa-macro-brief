# Live integration tests: these talk to statssa.gov.za and are OFF by default.
#
#   SA_BRIEF_LIVE_TESTS=true Rscript -e 'testthat::test_dir("tests")'
#
# They are excluded from CI on purpose. The offline suite covers parsing and
# analysis against committed fixtures; these verify the one thing fixtures
# cannot - that the live site still serves what the pipeline expects. Keep
# them few, so running them stays polite.

test_that("the CPI release is discoverable and downloadable end to end", {
  skip_unless_live()
  root <- proj_root
  paths <- fetch_release("cpi", "2026-07", root = root)
  expect_true(file.exists(paths$coicop))
  expect_true(file.exists(paths$digit8))

  long <- read_cpi_coicop(paths$coicop, period = "2026-07", root = root)
  expect_equal(series_value(long, "CPS00000", "2026-07"), 107.7)
})

test_that("fetched artefacts record honest provenance", {
  skip_unless_live()
  metas <- list.files(file.path(proj_root, "data-raw"), pattern = "\\.vintage\\.yaml$",
                      recursive = TRUE, full.names = TRUE)
  skip_if(length(metas) == 0, "nothing fetched yet")
  for (m in metas) {
    v <- yaml::read_yaml(m)
    expect_true(v$source %in% c("statssa", "wayback"))
    expect_true(nzchar(v$retrieved_at))
  }
})

test_that("the live site still serves every release the tool depends on", {
  skip_unless_live()
  expect_false(is.null(discover_by_probe("cpi", "2026-07", "coicop")))
  expect_false(is.null(discover_by_probe("ppi", "2026-06", "main")))
  expect_false(is.null(discover_by_probe("gdp", "2026Q1", "main")))
  expect_false(is.null(discover_by_probe("qlfs", "2026Q2", "main")))
})
