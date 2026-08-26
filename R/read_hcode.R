# Generic reader for the Stats SA H-code layout shared by CPI, PPI and GDP:
# row 1 is a header of H-codes for metadata columns followed by one column per
# period; one series per row, wide format, decimal points.

#' Read an H-code spreadsheet into long format.
#'
#' @param path xlsx path
#' @param sheet sheet name or index
#' @param expected_meta character vector of H-columns that must be present
#'   (e.g. c("H01","H02","H03",...)). Aborts with a named check on mismatch —
#'   a changed metadata layout must fail loudly, not shift columns silently.
#' @return long tibble: all metadata columns, series_code (= H03),
#'   period, date, freq, value. Blank cells map to NA, never zero.
read_hcode <- function(path, sheet = 1, expected_meta = NULL) {
  wide <- readxl::read_excel(path, sheet = sheet, col_types = "text",
                             .name_repair = "minimal")
  meta_cols <- names(wide)[grepl("^H\\d{2}$", names(wide))]
  # positional, NOT setdiff: duplicate column labels must survive (the GDP
  # Q1 2026 workbook carries a duplicated "201803" label)
  period_cols <- names(wide)[!names(wide) %in% meta_cols]

  if (!is.null(expected_meta)) {
    if (!setequal(meta_cols, expected_meta)) {
      stop("check_hcode_metadata_layout: metadata columns in '", basename(path),
           "' are [", paste(meta_cols, collapse = ","), "], expected [",
           paste(expected_meta, collapse = ","), "]", call. = FALSE)
    }
  }
  if (!"H03" %in% meta_cols) {
    stop("check_hcode_has_H03: no H03 series-code column in ", basename(path),
         call. = FALSE)
  }

  parsed <- parse_period(period_cols)
  bad <- period_cols[is.na(parsed$period)]
  if (length(bad) > 0) {
    stop("check_hcode_period_columns: unparseable period columns in ",
         basename(path), ": ", paste(utils::head(bad, 5), collapse = ", "),
         call. = FALSE)
  }
  # Repair a known Stats SA labelling defect: a period column duplicated while
  # its immediate successor is missing (the GDP Q1 2026 workbook labels the
  # 2018Q4 column "201803"). Only this exact, provable pattern is repaired —
  # the duplicate's position must be directly after the original and the
  # successor period absent; anything else still aborts on the duplicate check.
  dup_i <- which(duplicated(parsed$period))
  for (i in dup_i) {
    successor <- period_next(parsed$period[i])
    if (i > 1 && parsed$period[i - 1] == parsed$period[i] &&
        !successor %in% parsed$period) {
      message("Repairing mislabelled period column in ", basename(path), ": ",
              "second '", period_cols[i], "' at position ", i,
              " read as ", successor, " (see docs/OPEN_QUESTIONS.md)")
      fixed <- parse_period(successor)
      parsed$period[i] <- fixed$period
      parsed$date[i] <- fixed$date
      parsed$freq[i] <- fixed$freq
    }
  }

  # rename period columns to their canonical period ids BEFORE pivoting:
  # mapping by original column name would silently collapse duplicate labels
  pos <- which(!names(wide) %in% meta_cols)
  names(wide)[pos] <- parsed$period   # handles repeated original names too
  long <- tidyr::pivot_longer(wide, cols = dplyr::all_of(pos),
                              names_to = "period", values_to = "value_raw")
  key <- match(long$period, parsed$period)
  long$date <- parsed$date[key]
  long$freq <- parsed$freq[key]
  long$value <- parse_number(long$value_raw)
  long$series_code <- long$H03
  dplyr::select(long, -value_raw)
}

#' Deduplicate series that appear in more than one H04 presentation block
#' (e.g. CPS00000 sits under both "CPI Headline" and "All Items" in the CPI
#' COICOP file). Duplicates must be numerically identical; a conflict aborts.
dedupe_series <- function(long, prefer_h04 = NULL) {
  dup_codes <- unique(long$series_code[duplicated(paste(long$series_code, long$period))])
  if (length(dup_codes) == 0) return(long)
  for (code in dup_codes) {
    rows <- long[long$series_code == code, ]
    chk <- stats::aggregate(value ~ period, data = rows,
                            FUN = function(v) length(unique(v[!is.na(v)])))
    if (any(chk$value > 1)) {
      stop("check_duplicate_series_consistent: series ", code,
           " appears in multiple blocks with conflicting values", call. = FALSE)
    }
  }
  keep_first <- !duplicated(paste(long$series_code, long$period))
  if (!is.null(prefer_h04) && "H04" %in% names(long)) {
    long <- long[order(long$H04 != prefer_h04), ]
    keep_first <- !duplicated(paste(long$series_code, long$period))
  }
  long[keep_first, ]
}

#' Assert every expected series code is present (guards silent classification
#' drift). `codes` is a named character vector; names appear in the error.
assert_series_present <- function(long, codes) {
  missing <- codes[!codes %in% unique(long$series_code)]
  if (length(missing) > 0) {
    stop("check_expected_series_present: missing series code(s): ",
         paste(sprintf("%s (%s)", missing, names(missing)), collapse = ", "),
         call. = FALSE)
  }
  invisible(long)
}

#' Assert the requested period exists in the data (the guard against silently
#' fetching the wrong or superseded file).
assert_period_present <- function(long, period, what) {
  p <- parse_period_one(period)
  if (!p$period %in% long$period) {
    stop("check_reported_period_matches_requested: ", what,
         " does not contain requested period ", p$period,
         " (latest available: ", max(long$period[!is.na(long$value)]), ")",
         call. = FALSE)
  }
  invisible(long)
}

#' Load the series-code contract.
series_codes <- function(root = here::here()) {
  yaml::read_yaml(file.path(root, "config", "series_codes.yaml"))
}
