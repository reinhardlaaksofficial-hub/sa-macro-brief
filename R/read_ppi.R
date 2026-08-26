# PPI reader: same H-code design as CPI, fewer metadata columns.

PPI_META <- c("H01", "H02", "H03", "H04", "H05", "H17", "H18", "H25")

read_ppi_file <- function(path, period = NULL, root = here::here()) {
  long <- read_hcode(path, sheet = "Excel table for 2012 to 2026",
                     expected_meta = PPI_META)
  if (!any(long$H01 == "P0142.1", na.rm = TRUE)) {
    stop("check_ppi_publication_code: H01 is not P0142.1 in ", basename(path),
         call. = FALSE)
  }
  long <- dedupe_series(long)
  codes <- series_codes(root)$ppi
  assert_series_present(long, c(headline = codes$headline))
  base_h18 <- unique(stats::na.omit(long$H18[long$series_code == codes$headline]))
  if (!any(grepl("Dec 2023\\s*=\\s*100", base_h18))) {
    stop("check_ppi_base_period: headline H18 is '",
         paste(base_h18, collapse = "; "), "', expected 'Dec 2023=100'",
         call. = FALSE)
  }
  if (!is.null(period)) assert_period_present(long, period, "PPI file")
  long
}

#' Fetch and read everything needed for a PPI briefing period. The CPI COICOP
#' series rides along for the PPI-vs-CPI overlay chart (any cached CPI vintage
#' covering the PPI period suffices; CPI is published before PPI each month).
load_ppi <- function(period, refresh = FALSE, root = here::here()) {
  paths <- fetch_release("ppi", period, refresh = refresh, root = root)
  ppi <- read_ppi_file(paths$main, period = period, root = root)
  cpi_zip <- find_cached_artifact("cpi", "CPI\\(COICOP\\) from Jan 2008.*\\.zip$",
                                  NULL, root)
  cpi <- NULL
  if (!is.na(cpi_zip)) {
    xlsx <- unzip_cached(cpi_zip)
    xlsx <- xlsx[grepl("\\.xlsx?$", xlsx, ignore.case = TRUE)][1]
    cpi <- read_cpi_coicop(xlsx, root = root)
  }
  list(ppi = ppi, cpi = cpi, vintage = paths$vintage)
}
