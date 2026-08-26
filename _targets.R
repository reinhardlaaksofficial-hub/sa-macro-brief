# targets pipeline: the same fetch -> read -> transform -> render DAG the CLI
# drives, for reproducible batch rebuilds of all four briefs.
#
#   Rscript -e 'targets::tar_make()'
#
# Periods default to the latest release each cached input covers; edit here
# on release day or use the CLI for ad-hoc periods.
library(targets)

tar_option_set(packages = character(0))  # functions are sourced, not attached
for (f in sort(list.files("R", pattern = "\\.R$", full.names = TRUE))) source(f)

PERIODS <- list(cpi = "2026-07", ppi = "2026-06", gdp = "2026Q1", qlfs = "2026Q2")

list(
  tar_target(cpi_data, load_cpi(PERIODS$cpi)),
  tar_target(cpi_transformed, add_cpi_analytics(
    transform_cpi(cpi_data, PERIODS$cpi), cpi_data)),
  tar_target(cpi_pdf, render_brief(payload_cpi(cpi_transformed)), format = "file"),

  tar_target(ppi_data, load_ppi(PERIODS$ppi)),
  tar_target(ppi_transformed, transform_ppi(ppi_data, PERIODS$ppi)),
  tar_target(ppi_pdf, render_brief(payload_ppi(ppi_transformed)), format = "file"),

  tar_target(gdp_data, load_gdp(PERIODS$gdp)),
  tar_target(gdp_transformed, transform_gdp(gdp_data, PERIODS$gdp)),
  tar_target(gdp_pdf, render_brief(payload_gdp(gdp_transformed)), format = "file"),

  tar_target(qlfs_data, load_qlfs(PERIODS$qlfs)),
  tar_target(qlfs_transformed, transform_qlfs(qlfs_data, PERIODS$qlfs)),
  tar_target(qlfs_pdf, render_brief(payload_qlfs(qlfs_transformed)), format = "file")
)
