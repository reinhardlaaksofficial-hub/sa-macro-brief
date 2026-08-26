# PPI and GDP reader tests against cached release files.
# Known-good values from the brief:
#   PPI Jun 2026 (PPC30000): index 110,3; y/y 7,5; m/m -0,1
#   GDP Q1 2026 (QRS1000): level 4 772 090,6; q/q sa 0,5; prior 0,4;
#   finance contribution 0,2 pp; manufacturing -0,1 pp

ppi_paths <- tryCatch(fetch_release("ppi", "2026-06", root = here::here()),
                      error = function(e) NULL)
gdp_paths <- tryCatch(fetch_release("gdp", "2026Q1", root = here::here()),
                      error = function(e) NULL)

test_that("read_ppi_file reproduces the June 2026 release values", {
  skip_if(is.null(ppi_paths), "PPI June 2026 file not cached")
  long <- read_ppi_file(ppi_paths$main, period = "2026-06")
  expect_equal(series_value(long, "PPC30000", "2026-06"), 110.3)
  expect_equal(round(pct_change(long, "PPC30000", "2026-06", 12), 1), 7.5)
  expect_equal(round(pct_change(long, "PPC30000", "2026-06", 1), 1), -0.1)
  # hierarchy anchors descend by code
  for (code in c("PPC31000", "PPC31100", "PPC31110", "PPC31111")) {
    expect_true(code %in% long$series_code, label = paste(code, "present"))
  }
})

test_that("read_gdp_file reproduces the Q1 2026 release values", {
  skip_if(is.null(gdp_paths), "GDP Q1 2026 file not cached")
  long <- suppressMessages(read_gdp_file(gdp_paths$main, period = "2026Q1"))
  expect_equal(series_value(long, "QRS1000", "2026Q1"), 4772090.6, tolerance = 1e-6)
  expect_equal(series_value(long, "QNU1000", "2026Q1"), 1938242.7, tolerance = 1e-6)
  expect_equal(series_value(long, "QNS1000", "2026Q1"), 8024549.3, tolerance = 1e-6)
  expect_equal(series_value(long, "QRU1000", "2026Q1"), 1167288.2, tolerance = 1e-6)
  expect_equal(round(pct_change(long, "QRS1000", "2026Q1", 1), 1), 0.5)
  expect_equal(round(pct_change(long, "QRS1000", "2025Q4", 1), 1), 0.4)
})

test_that("the duplicated 201803 column is repaired to 2018Q4, not dropped", {
  skip_if(is.null(gdp_paths), "GDP Q1 2026 file not cached")
  expect_message(read_gdp_file(gdp_paths$main), "2018Q4")
  long <- suppressMessages(read_gdp_file(gdp_paths$main))
  # one observation per series-period, and 2018Q4 exists with the seasonal
  # agriculture trough that identifies it
  agri <- long[long$series_code == "QNU1001" & long$period %in%
                 c("2018Q3", "2018Q4"), ]
  expect_equal(nrow(agri), 2L)
  expect_lt(agri$value[agri$period == "2018Q4"],
            agri$value[agri$period == "2018Q3"])
})

test_that("GDP contributions reconcile with the headline within tolerance", {
  skip_if(is.null(gdp_paths), "GDP Q1 2026 file not cached")
  d <- suppressMessages(load_gdp("2026Q1"))
  t <- transform_gdp(d, "2026Q1")
  expect_equal(round(t$contributions$pp[t$contributions$key == "finance_real_estate_business"], 1), 0.2)
  expect_equal(round(t$contributions$pp[t$contributions$key == "manufacturing"], 1), -0.1)
  expect_lt(abs(sum(t$contributions$pp) - t$headline$qq), 0.06)
})

test_that("read_gdp_concordance loads the SARB mapping", {
  skip_if(is.null(gdp_paths), "GDP Q1 2026 file not cached")
  cc <- read_gdp_concordance(gdp_paths$main)
  expect_true("SARB code (quarterly series)" %in% names(cc))
  expect_gt(nrow(cc), 100)
})
