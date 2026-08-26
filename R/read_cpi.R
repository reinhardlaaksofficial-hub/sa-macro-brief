# CPI readers: the COICOP H-code file (index levels, 2008-) and the 8-digit
# product file (named columns, the only file with weights).

CPI_COICOP_META <- c("H01", "H02", "H03", "H04", "H05", "H06",
                     "H13", "H17", "H18", "H24", "H25")

CPI_8DIGIT_ID_COLS <- c("Division", "DivisionDescription", "Group",
                        "GroupDescription", "Class", "ClassDescription",
                        "Subclass", "SubclassDescription", "Old code",
                        "Eight digit code", "Product name", "Weight",
                        "Base period")

#' Read the CPI COICOP file to long format with integrity checks.
read_cpi_coicop <- function(path, period = NULL, root = here::here()) {
  long <- read_hcode(path, sheet = "Excel table from 2008",
                     expected_meta = CPI_COICOP_META)
  if (!any(long$H01 == "P0141", na.rm = TRUE)) {
    stop("check_cpi_publication_code: H01 is not P0141 in ", basename(path),
         call. = FALSE)
  }
  # CPS00000 appears under both "CPI Headline" and "All Items"; keep the
  # headline block after confirming the values agree.
  long <- dedupe_series(long, prefer_h04 = "CPI Headline")

  codes <- series_codes(root)$cpi
  expected <- c(headline = codes$headline, core = codes$core,
                unlist(codes$divisions))
  assert_series_present(long, expected)

  # the base regime printed in the file must match the configured break
  base_h18 <- unique(stats::na.omit(long$H18[long$series_code == codes$headline]))
  if (!any(grepl("Dec 2024\\s*=\\s*100", base_h18))) {
    stop("check_cpi_base_period: headline H18 is '",
         paste(base_h18, collapse = "; "), "', expected 'Dec 2024 = 100'",
         call. = FALSE)
  }
  # label sanity for core: the code is the key, but if the label no longer
  # says what the definition requires, the contract must be re-verified
  core_lab <- unique(stats::na.omit(long$H05[long$series_code == codes$core]))
  if (!any(grepl("excl food and NAB, fuel and energy", core_lab, ignore.case = TRUE))) {
    stop("check_cpi_core_label: core series ", codes$core, " is labelled '",
         paste(core_lab, collapse = "; "),
         "', expected 'CPI excl food and NAB, fuel and energy'", call. = FALSE)
  }
  if (!is.null(period)) assert_period_present(long, period, "CPI COICOP file")
  long
}

#' Read the CPI 8-digit product file (COICOP 2018): named columns, product
#' weights, and Stats SA's own old-code concordance. Blank cells where a
#' product's history starts later map to NA, never zero.
read_cpi_products <- function(path) {
  wide <- readxl::read_excel(path, col_types = "text", .name_repair = "minimal")
  missing_cols <- setdiff(CPI_8DIGIT_ID_COLS, names(wide))
  if (length(missing_cols) > 0) {
    stop("check_cpi8_columns: 8-digit file missing column(s): ",
         paste(missing_cols, collapse = ", "), call. = FALSE)
  }
  period_cols <- names(wide)[grepl("^M\\d{6}$", names(wide))]
  if (length(period_cols) == 0) {
    stop("check_cpi8_period_columns: no M-prefixed period columns found",
         call. = FALSE)
  }
  wide$Weight <- parse_number(wide$Weight)
  wsum <- sum(wide$Weight, na.rm = TRUE)
  if (abs(wsum - 100) > 0.05) {
    stop("check_cpi_weights_sum_100: product weights sum to ", round(wsum, 3),
         ", expected 100.00", call. = FALSE)
  }
  long <- tidyr::pivot_longer(wide, cols = dplyr::all_of(period_cols),
                              names_to = "period_raw", values_to = "value_raw")
  parsed <- parse_period(long$period_raw)
  long$period <- parsed$period
  long$date <- parsed$date
  long$value <- parse_number(long$value_raw)
  long$product_code <- long[["Eight digit code"]]
  dplyr::select(long, -period_raw, -value_raw)
}

#' Fetch and read everything needed for a CPI briefing period.
load_cpi <- function(period, refresh = FALSE, root = here::here()) {
  paths <- fetch_release("cpi", period, refresh = refresh, root = root)
  coicop <- read_cpi_coicop(paths$coicop, period = period, root = root)
  products <- read_cpi_products(paths$digit8)
  list(coicop = coicop, products = products, vintage = paths$vintage)
}
