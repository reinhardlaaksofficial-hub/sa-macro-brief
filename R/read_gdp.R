# GDP reader: Quarterly sheet of the time-series workbook, plus the
# Concordance (Q) sheet (Stats SA code -> SARB code -> old Stats SA code),
# which is how the pipeline survives the pending 2022-base rebasing.
#
# Series codes decode as Q + N(current)/R(constant 2015) + U(actual)/
# S(seasonally adjusted and annualised) + four digits. The QRS1000 *levels*
# are annualised; growth computed from them is q/q sa, NOT annualised.

GDP_META <- c("H01", "H02", "H03", "H04", "H05", "H06", "H15", "H16", "H17", "H25")

read_gdp_file <- function(path, period = NULL, root = here::here()) {
  sheets <- readxl::excel_sheets(path)
  # sheet names carry a trailing space ("Quarterly Coe seasonal "): match trimmed
  qsheet <- sheets[trimws(sheets) == "Quarterly"][1]
  if (is.na(qsheet)) {
    stop("check_gdp_quarterly_sheet: no 'Quarterly' sheet in ", basename(path),
         call. = FALSE)
  }
  long <- read_hcode(path, sheet = qsheet, expected_meta = GDP_META)
  if (!any(long$H01 == "P0441", na.rm = TRUE)) {
    stop("check_gdp_publication_code: H01 is not P0441 in ", basename(path),
         call. = FALSE)
  }
  long <- dedupe_series(long)
  codes <- series_codes(root)$gdp
  assert_series_present(long, c(headline = codes$headline_constant_saa,
                                value_added_total = codes$value_added_total,
                                taxes = codes$taxes_less_subsidies,
                                unlist(codes$industries_saa)))
  # price-basis sanity on the headline: must be constant 2015, sa & annualised
  h15 <- unique(stats::na.omit(long$H15[long$series_code == codes$headline_constant_saa]))
  h16 <- unique(stats::na.omit(long$H16[long$series_code == codes$headline_constant_saa]))
  if (!any(grepl("Constant 2015", h15)) || !any(grepl("Seasonally adjusted and annualised", h16))) {
    stop("check_gdp_headline_basis: QRS1000 basis is '", paste(h15, h16, collapse = " / "),
         "', expected constant 2015 prices, seasonally adjusted and annualised",
         call. = FALSE)
  }
  if (!is.null(period)) assert_period_present(long, period, "GDP Quarterly sheet")
  long
}

#' Concordance (Q): Stats SA quarterly code -> SARB code -> old Stats SA code.
read_gdp_concordance <- function(path) {
  sheets <- readxl::excel_sheets(path)
  csheet <- sheets[trimws(sheets) == "Concordance (Q)"][1]
  if (is.na(csheet)) {
    stop("check_gdp_concordance_sheet: no 'Concordance (Q)' sheet in ",
         basename(path), call. = FALSE)
  }
  cc <- readxl::read_excel(path, sheet = csheet, col_types = "text",
                           .name_repair = "minimal")
  names(cc) <- stringr::str_squish(names(cc))
  needed <- c("Stats SA code (quarterly series)", "SARB code (quarterly series)")
  missing <- setdiff(needed, names(cc))
  if (length(missing) > 0) {
    stop("check_gdp_concordance_columns: missing ", paste(missing, collapse = ", "),
         call. = FALSE)
  }
  cc
}

load_gdp <- function(period, refresh = FALSE, root = here::here()) {
  paths <- fetch_release("gdp", period, refresh = refresh, root = root)
  long <- read_gdp_file(paths$main, period = period, root = root)
  concordance <- read_gdp_concordance(paths$main)
  list(gdp = long, concordance = concordance, vintage = paths$vintage)
}
