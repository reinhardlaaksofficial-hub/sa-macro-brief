# QLFS PDF parser. The QLFS is published as PDF only; Table A (key labour
# market indicators) and Table B (employment by industry) are extracted from
# pdftools::pdf_text() output.
#
# Landmines handled here: decimal commas ("33,6"), space-separated thousands
# ("41 822"), ".." and blanks both meaning NA, repeated page furniture,
# wrapped row labels (LU2/LU3/LU4 wrap around their own value line), and the
# Q3:2025 informality break (formal/informal rows carry values only for
# comparable quarters).
#
# The report covers ages 15-64, not 15+.

#' Split a table line into label and numeric tokens. Columns are separated by
#' runs of 2+ spaces; single spaces inside numbers are thousands separators
#' and are stripped before parsing.
qlfs_split_line <- function(line) {
  line <- gsub("[   ]", " ", line)
  parts <- strsplit(trimws(line), "\\s{2,}")[[1]]
  if (length(parts) == 0) return(list(label = "", values = numeric(0)))
  numlike <- grepl("^-?[0-9][0-9 ]*(,[0-9]+)?$|^\\.\\.$|^-$", parts)
  # the label is the leading run of non-numeric parts (a label may itself
  # contain single spaces; it never contains a run of 2+ spaces)
  first_num <- if (any(numlike)) which(numlike)[1] else length(parts) + 1L
  label <- paste(parts[seq_len(first_num - 1)], collapse = " ")
  vals <- parts[seq(first_num, length.out = max(0, length(parts) - first_num + 1))]
  list(label = stringr::str_squish(label), values = parse_number(vals))
}

#' Quarter id from a QLFS column header pair like "Apr-Jun" + "2026".
qlfs_quarter <- function(months, year) {
  q <- c("Jan-Mar" = 1, "Apr-Jun" = 2, "Jul-Sep" = 3, "Oct-Dec" = 4)[months]
  sprintf("%sQ%d", year, q)
}

#' Extract the three period ids from a Table A/B header block.
qlfs_header_periods <- function(page_lines) {
  rx <- "(Jan-Mar|Apr-Jun|Jul-Sep|Oct-Dec)"
  mline <- which(lengths(stringr::str_extract_all(page_lines, rx)) >= 3)[1]
  if (is.na(mline)) {
    stop("check_qlfs_header_periods: month header row not found", call. = FALSE)
  }
  months <- stringr::str_extract_all(page_lines[mline], rx)[[1]][1:3]
  # years share the header line in some vintages, or sit on the next line(s)
  years <- character(0)
  for (li in mline:min(mline + 2, length(page_lines))) {
    years <- c(years, stringr::str_extract_all(page_lines[li], "\\b20\\d{2}\\b")[[1]])
    if (length(years) >= 3) break
  }
  if (length(years) < 3) {
    stop("check_qlfs_header_periods: could not read three period years",
         call. = FALSE)
  }
  vapply(1:3, function(i) qlfs_quarter(months[i], years[i]), "")
}

# Table A rows, in published order. type: "level" (7 columns: three levels,
# q/q and y/y change in thousands, q/q and y/y change in per cent),
# "level_break" (informality: only post-break quarters populated),
# "rate" (5 columns: three levels, then q/q and y/y change in PERCENTAGE
# POINTS despite the % header).
QLFS_TABLE_A_ROWS <- list(
  list(label = "Population 15-64 years",              key = "population_15_64",  type = "level"),
  list(label = "Labour Force",                        key = "labour_force",      type = "level"),
  list(label = "Employed",                            key = "employed",          type = "level"),
  list(label = "Formal sector*",                      key = "formal_sector",     type = "level_break"),
  list(label = "Informal sector*",                    key = "informal_sector",   type = "level_break"),
  list(label = "Household sector",                    key = "household_sector",  type = "level"),
  list(label = "Unemployed",                          key = "unemployed",        type = "level"),
  list(label = "Outside the Labour Force",            key = "outside_lf",        type = "level"),
  list(label = "Potential Labour Force",              key = "potential_lf",      type = "level"),
  list(label = "Available job-seekers",               key = "available_seekers", type = "level"),
  list(label = "Discouraged job-seekers",             key = "discouraged",       type = "level"),
  list(label = "Other (available job-seekers)",       key = "other_available",   type = "level"),
  list(label = "Unavailable job-seekers",             key = "unavailable_seekers", type = "level"),
  list(label = "Other (Outside the labour force)",    key = "other_outside",     type = "level"),
  list(label = "Labour force participation rate",     key = "participation_rate", type = "rate"),
  list(label = "Employed / population ratio (Absorption)", key = "absorption_rate", type = "rate"),
  list(label = "Inactivity rate",                     key = "inactivity_rate",   type = "rate"),
  list(label = "LU1- Unemployment rate",              key = "lu1",               type = "rate"),
  list(label = "LU2 - Combined rate of unemployment and time-related", key = "lu2", type = "rate"),
  list(label = "LU3 - Combined rate of unemployment and potential labour", key = "lu3", type = "rate"),
  list(label = "LU4 - Composite measure of labour underutilisation", key = "lu4", type = "rate")
)

#' Parse Table A from the full pdf_text() vector. Returns a tidy data.frame:
#' key, label, type, then q_yr_ago/q_prev/q_now levels, qq_change, yy_change
#' (thousands), qq_pct, yy_pct (per cent for levels, NA for rates),
#' qq_pp, yy_pp (percentage points, rates only).
parse_qlfs_table_a <- function(txt) {
  page_i <- which(grepl("Table A: Key labour market indicators", txt) &
                  grepl("Population 15-64", txt))[1]
  if (is.na(page_i)) {
    stop("check_qlfs_table_a_found: Table A page not located", call. = FALSE)
  }
  lines <- strsplit(txt[page_i], "\n")[[1]]
  periods <- qlfs_header_periods(lines[seq_len(min(40, length(lines)))])

  out <- list()
  for (spec in QLFS_TABLE_A_ROWS) {
    li <- which(startsWith(trimws(gsub("\\s+", " ", lines)),
                           spec$label))[1]
    if (is.na(li)) {
      warning("QLFS Table A row not found: ", spec$label, " - recorded as not available")
      vals <- numeric(0)
    } else {
      vals <- qlfs_split_line(lines[li])$values
      # wrapped labels (LU2/LU3): the label line carries no numbers; the
      # values sit on the following line, with the label's tail after them
      if (length(vals) == 0 && li < length(lines)) {
        vals <- qlfs_split_line(lines[li + 1])$values
      }
    }
    row <- list(key = spec$key, label = spec$label, type = spec$type,
                q_yr_ago = NA_real_, q_prev = NA_real_, q_now = NA_real_,
                qq_change = NA_real_, yy_change = NA_real_,
                qq_pct = NA_real_, yy_pct = NA_real_,
                qq_pp = NA_real_, yy_pp = NA_real_)
    if (spec$type == "level" && length(vals) >= 7) {
      row[c("q_yr_ago", "q_prev", "q_now", "qq_change", "yy_change",
            "qq_pct", "yy_pct")] <- as.list(vals[1:7])
    } else if (spec$type == "level_break" && length(vals) >= 4) {
      # informality: only Q3:2025-onward quarters are mutually comparable, so
      # the year-ago level and y/y columns are blank in the release
      row[c("q_prev", "q_now", "qq_change", "qq_pct")] <- as.list(vals[1:4])
    } else if (spec$type == "rate" && length(vals) >= 5) {
      # despite the % header, changes in a rate are percentage points
      row[c("q_yr_ago", "q_prev", "q_now", "qq_pp", "yy_pp")] <- as.list(vals[1:5])
    }
    out[[spec$key]] <- as.data.frame(row, stringsAsFactors = FALSE)
  }
  res <- do.call(rbind, out)
  attr(res, "periods") <- periods
  res
}

#' Parse Table B (employment by industry) into industry, three levels,
#' q/q and y/y change in thousands, q/q and y/y change in per cent.
parse_qlfs_table_b <- function(txt) {
  page_i <- which(grepl("Table B: Employment by industry", txt) &
                  grepl("Agriculture", txt))[1]
  if (is.na(page_i)) {
    stop("check_qlfs_table_b_found: Table B page not located", call. = FALSE)
  }
  lines <- strsplit(txt[page_i], "\n")[[1]]
  industries <- c("Total*", "Agriculture", "Mining", "Manufacturing", "Utilities",
                  "Construction", "Trade", "Transport", "Finance",
                  "Community and social services", "Private households")
  rows <- list()
  for (ind in industries) {
    li <- which(startsWith(trimws(gsub("\\s+", " ", lines)), ind))[1]
    if (is.na(li)) {
      warning("QLFS Table B row not found: ", ind); next
    }
    vals <- qlfs_split_line(lines[li])$values
    if (length(vals) < 7) next
    rows[[ind]] <- data.frame(
      industry = sub("\\*$", "", ind),
      q_yr_ago = vals[1], q_prev = vals[2], q_now = vals[3],
      qq_change = vals[4], yy_change = vals[5],
      qq_pct = vals[6], yy_pct = vals[7], stringsAsFactors = FALSE)
  }
  do.call(rbind, rows)
}

#' QLFS integrity checks (all in thousands, tolerance for published rounding).
assert_qlfs_identities <- function(a) {
  g <- function(k, col = "q_now") a[a$key == k, col]
  tol <- 3  # thousands; published components are independently rounded
  if (abs(g("employed") + g("unemployed") - g("labour_force")) > tol) {
    stop("check_qlfs_employed_plus_unemployed: employed + unemployed != labour force",
         call. = FALSE)
  }
  if (abs(g("labour_force") + g("outside_lf") - g("population_15_64")) > tol) {
    stop("check_qlfs_labour_force_plus_outside: labour force + outside LF != working-age population",
         call. = FALSE)
  }
  rates <- a[a$type == "rate", "q_now"]
  if (any(!is.na(rates) & (rates < 0 | rates > 100))) {
    stop("check_qlfs_rates_plausible: a rate falls outside 0-100", call. = FALSE)
  }
  lu1 <- g("lu1"); lu3 <- g("lu3")
  if (!is.na(lu1) && !is.na(lu3) && lu3 < lu1) {
    stop("check_qlfs_lu3_geq_lu1: LU3 below LU1 is implausible", call. = FALSE)
  }
  invisible(a)
}

#' The reported period on the PDF cover must match the requested period.
assert_qlfs_cover <- function(txt, period) {
  cover <- paste(txt[1:2], collapse = " ")
  m <- stringr::str_match(cover, "Quarter\\s*(\\d)\\s*:\\s*(\\d{4})")
  if (is.na(m[1, 1]) || sprintf("%sQ%s", m[1, 3], m[1, 2]) != period) {
    stop("check_reported_period_matches_requested: PDF cover says Q", m[1, 2],
         " ", m[1, 3], ", requested ", period, call. = FALSE)
  }
  invisible(TRUE)
}

#' Fetch and parse the QLFS for one quarter.
load_qlfs <- function(period, refresh = FALSE, root = here::here()) {
  p <- parse_period_one(period)
  paths <- fetch_release("qlfs", period, refresh = refresh, root = root)
  txt <- pdftools::pdf_text(paths$main)
  assert_qlfs_cover(txt, p$period)

  table_a <- parse_qlfs_table_a(txt)
  assert_qlfs_identities(table_a)
  table_b <- parse_qlfs_table_b(txt)
  list(table_a = table_a, table_b = table_b,
       periods = attr(table_a, "periods"), vintage = paths$vintage)
}
