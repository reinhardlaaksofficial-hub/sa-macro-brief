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
  # Never pin a period here: Stats SA keeps only the CURRENT vintage of the
  # timeseries files and deletes the previous one, so a hardcoded month
  # starts failing within weeks. Walk recent periods and require that at
  # least one resolves for each release.
  resolves_recently <- function(release, key, freq, n = 4) {
    for (p in recent_periods(freq, n)) {
      hit <- tryCatch(discover_by_probe(release, p, key), error = function(e) NULL)
      if (!is.null(hit)) return(TRUE)
    }
    FALSE
  }
  expect_true(resolves_recently("cpi",  "coicop", "monthly"))
  expect_true(resolves_recently("ppi",  "main",   "monthly"))
  expect_true(resolves_recently("gdp",  "main",   "quarterly"))
  expect_true(resolves_recently("qlfs", "main",   "quarterly"))
})
