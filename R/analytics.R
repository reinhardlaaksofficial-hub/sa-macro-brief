# Analysis beyond arithmetic: inflation breadth, contributions with
# reconciliation, and revision tracking. See docs/METHODOLOGY.md for the
# formal definitions.

#' Inflation breadth: the share of CPI weight inflating above the target
#' midpoint, monthly. Computed from the 8-digit product file (the only file
#' with weights). Products whose y/y is not computable in a month (history
#' starts later, or a missing observation) are excluded from BOTH numerator
#' and denominator for that month; the share is of measurable weight.
compute_breadth <- function(products, midpoint = 4.5) {
  prod <- products[!is.na(products$Weight), ]
  prod <- prod[order(prod$product_code, prod$date), ]
  yy <- dplyr::mutate(
    dplyr::group_by(prod, product_code),
    yy = 100 * (value / dplyr::lag(value, 12) - 1)
  )
  yy <- dplyr::ungroup(yy)
  yy <- yy[!is.na(yy$yy), ]
  agg <- dplyr::summarise(
    dplyr::group_by(yy, period, date),
    share = 100 * sum(Weight[yy > midpoint]) / sum(Weight),
    coverage = sum(Weight),
    .groups = "drop"
  )
  as.data.frame(agg[order(agg$date), ])
}

#' CPI division contributions to headline y/y, in pp, from weight x index
#' change: contribution_i = (w_i/100) * yy_i * (I_i,t-12 / I_head,t-12).
#' The last factor re-prices the weight (fixed at the Dec 2024 basket) to the
#' comparison month, which is what makes the contributions add up.
#' Division weights are the sums of the 8-digit product weights per division.
compute_cpi_contributions <- function(coicop, products, period,
                                      root = here::here()) {
  codes <- series_codes(root)$cpi
  w <- unique(products[!is.na(products$Weight),
                       c("Division", "product_code", "Weight")])
  div_w <- tapply(w$Weight, w$Division, sum)

  # division key -> two-digit COICOP division id (from the H03 code CPSdd...)
  div_ids <- substr(unlist(codes$divisions), 4, 5)
  names(div_ids) <- names(codes$divisions)

  head_lag <- series_value(coicop, codes$headline, period_lag(period, 12))
  rows <- lapply(names(codes$divisions), function(k) {
    code <- codes$divisions[[k]]
    yy <- pct_change(coicop, code, period, 12)
    lag_i <- series_value(coicop, code, period_lag(period, 12))
    weight <- div_w[[div_ids[[k]]]]
    if (is.null(weight)) weight <- NA_real_
    data.frame(key = k, code = code, weight = weight, yy = yy,
               pp = (weight / 100) * yy * (lag_i / head_lag),
               stringsAsFactors = FALSE)
  })
  contrib <- do.call(rbind, rows)

  headline_yy <- pct_change(coicop, codes$headline, period, 12)
  gap <- sum(contrib$pp, na.rm = TRUE) - headline_yy
  attr(contrib, "headline_yy") <- headline_yy
  attr(contrib, "gap") <- gap
  # published index levels are rounded to one decimal; a tolerance of 0,15 pp
  # absorbs that rounding across 13 divisions
  if (is.na(gap) || abs(gap) > 0.15) {
    stop("check_cpi_contributions_reconcile: division contributions sum to ",
         round(sum(contrib$pp, na.rm = TRUE), 2), " vs headline y/y ",
         round(headline_yy, 2), call. = FALSE)
  }
  contrib
}

#' Reconcile computed contributions against the release PDF's Table C, if the
#' release PDF is cached. Returns a data.frame of comparisons or NULL when the
#' PDF is unavailable (the internal sum-to-headline check still ran).
reconcile_contributions_pdf <- function(contrib, period, root = here::here()) {
  p <- parse_period_one(period)
  tag <- format(p$date, "%B%Y")
  pdf <- find_cached_artifact("cpi", paste0("^P0141", tag, "\\.pdf$"), NULL, root)
  if (is.na(pdf)) return(NULL)
  reconcile_contributions_text(contrib, pdftools::pdf_text(pdf))
}

#' Reconcile against Table C given the release PDF's text. Split out from the
#' path-based wrapper so it can be tested from a small text fixture instead of
#' a redistributed PDF.
reconcile_contributions_text <- function(contrib, txt) {
  # the contents page also matches "Table C"; the data page carries "All items"
  page_i <- which(grepl("Table C", txt) & grepl("[Cc]ontribution", txt) &
                  grepl("All items", txt))[1]
  if (is.na(page_i)) return(NULL)
  lines <- strsplit(txt[page_i], "\n")[[1]]
  cmp <- contrib
  cmp$published <- NA_real_
  labels <- c(food_nab = "Food and non-alcoholic beverages",
              alcohol_tobacco = "Alcoholic beverages and tobacco",
              clothing_footwear = "Clothing and footwear",
              housing_utilities = "Housing and utilities",
              furnishings = "Furnishings",
              health = "Health", transport = "Transport",
              information_communication = "Information and communication",
              recreation_culture = "Recreation",
              education = "Education", restaurants_accommodation = "Restaurants",
              insurance_financial = "Insurance and financial services",
              personal_care_misc = "Personal care")
  for (k in names(labels)) {
    li <- grep(labels[[k]], lines, ignore.case = TRUE)[1]
    if (is.na(li)) next
    vals <- qlfs_split_line(lines[li])$values
    # Table C rows: weight, then m/m %, m/m pp, y/y %, y/y pp — the final
    # numeric token is the y/y contribution
    if (length(vals) >= 2) cmp$published[cmp$key == k] <- vals[length(vals)]
  }
  cmp$diff <- cmp$pp - cmp$published
  bad <- !is.na(cmp$published) & abs(cmp$diff) > 0.1
  if (any(bad)) {
    stop("check_cpi_contributions_match_table_c: computed contribution differs ",
         "from the release PDF by more than 0,1 pp for: ",
         paste(cmp$key[bad], collapse = ", "), call. = FALSE)
  }
  cmp
}

#' Attach breadth and contributions to a CPI transform result.
add_cpi_analytics <- function(t, cpi, root = here::here()) {
  breadth <- compute_breadth(cpi$products)
  t$breadth <- breadth
  latest <- utils::tail(breadth, 1)
  t$breadth_now <- latest$share
  t$breadth_asof <- period_label(latest$period)
  if (latest$period < t$period) {
    t$flags <- c(t$flags, sprintf(
      "Breadth is computed from the %s vintage of the 8-digit product file, the newest obtainable at build time.",
      period_label(latest$period)))
  }
  contrib <- compute_cpi_contributions(cpi$coicop, cpi$products, t$period, root)
  t$contributions <- contrib
  t$contrib_reconciliation <- reconcile_contributions_pdf(contrib, t$period, root)
  t
}

#' GDP revision tracking: how much each first-printed q/q growth figure moves
#' across subsequent vintages, from the accumulated snapshot store.
#' Returns one row per data period with first and latest prints, or an empty
#' frame until at least two vintages have been observed.
gdp_revision_history <- function(root = here::here()) {
  path <- file.path(root, "data", "vintages", "gdp.csv")
  empty <- data.frame(period = character(0), first_print = numeric(0),
                      latest = numeric(0), revision_pp = numeric(0))
  if (!file.exists(path)) return(empty)
  store <- utils::read.csv(path, colClasses = c(value = "numeric"))
  store <- store[store$series_code == series_codes(root)$gdp$headline_constant_saa, ]
  if (length(unique(store$vintage)) < 2) return(empty)
  qq_by_vintage <- do.call(rbind, lapply(split(store, store$vintage), function(s) {
    s <- s[order(s$period), ]
    data.frame(vintage = s$vintage,
               period = s$period,
               qq = 100 * (s$value / dplyr::lag(s$value, 1) - 1))
  }))
  qq_by_vintage <- qq_by_vintage[!is.na(qq_by_vintage$qq), ]
  out <- do.call(rbind, lapply(split(qq_by_vintage, qq_by_vintage$period), function(s) {
    s <- s[order(s$vintage), ]
    data.frame(period = s$period[1], first_print = s$qq[1],
               latest = s$qq[nrow(s)],
               revision_pp = s$qq[nrow(s)] - s$qq[1])
  }))
  rownames(out) <- NULL
  out
}
