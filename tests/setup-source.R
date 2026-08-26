# Sourced automatically by testthat::test_dir("tests").
# Loads every function under R/ so tests run against the working tree.
proj_root <- normalizePath(file.path(testthat::test_path(), ".."), mustWork = TRUE)
for (f in sort(list.files(file.path(proj_root, "R"), pattern = "\\.R$", full.names = TRUE))) {
  source(f, local = FALSE)
}

fixture_path <- function(...) file.path(proj_root, "tests", "testthat", "fixtures", ...)

# The default suite runs entirely offline against small committed fixtures:
# cloning this repository must never mean downloading from - or repeatedly
# hitting - a government statistics server. Tests that talk to statssa.gov.za
# are opt-in:
#
#   SA_BRIEF_LIVE_TESTS=true Rscript -e 'testthat::test_dir("tests")'
live_tests_enabled <- function() {
  isTRUE(tolower(Sys.getenv("SA_BRIEF_LIVE_TESTS", "false")) %in% c("true", "1", "yes"))
}

skip_unless_live <- function() {
  testthat::skip_if_not(live_tests_enabled(),
                        "live Stats SA tests disabled (set SA_BRIEF_LIVE_TESTS=true)")
}

# Fixture accessors, mirroring what fetch_release() returns for a real run.
fx_cpi <- function() list(coicop = fixture_path("cpi_coicop_sample.xlsx"),
                          digit8 = fixture_path("cpi_products_sample.xlsx"))
fx_ppi <- function() list(main = fixture_path("ppi_sample.xlsx"))
fx_gdp <- function() list(main = fixture_path("gdp_sample.xlsx"))
fx_qlfs_text <- function() readRDS(fixture_path("qlfs_2026Q2_text.rds"))
fx_tablec_text <- function() readRDS(fixture_path("cpi_2026-07_tablec_text.rds"))

# The fixture CPI files stand in for a fetched release, so the readers and
# analytics can be exercised without touching the network.
fx_cpi_data <- function() {
  paths <- fx_cpi()
  list(coicop = read_cpi_coicop(paths$coicop, root = proj_root),
       products = read_cpi_products(paths$digit8),
       vintage = list(list(retrieved_at = "2026-08-26 00:00:00 UTC",
                           source = "fixture")))
}
