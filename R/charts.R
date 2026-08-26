# Chart builders. Each returns a ggplot object; render.R decides file layout.
# House rules: one accent colour; comparison series in dark ink with a
# distinct linetype and a direct label; the 3-6% target band shaded with the
# 4.5% midpoint marked; muted gridlines; no chart junk; no pie charts.

#' Headline vs core y/y over five years with the inflation target band.
chart_cpi_headline_core <- function(t) {
  h <- t$history
  pol <- t$policy
  ends <- do.call(rbind, lapply(split(h, h$series), function(d) d[which.max(d$date), ]))
  # keep end labels apart when the two series finish close together
  ends <- ends[order(ends$yy), ]
  if (nrow(ends) == 2 && diff(ends$yy) < 0.06 * diff(range(h$yy))) {
    gap <- 0.04 * diff(range(h$yy))
    ends$yy <- ends$yy + c(-gap, gap)
  }
  ggplot2::ggplot(h, ggplot2::aes(date, yy, group = series)) +
    ggplot2::annotate("rect", xmin = min(h$date), xmax = max(h$date),
                      ymin = pol$lower, ymax = pol$upper,
                      fill = BRIEF_BAND, alpha = 0.08) +
    ggplot2::geom_hline(yintercept = pol$midpoint, colour = BRIEF_GREY,
                        linetype = "dotted", linewidth = 0.35) +
    ggplot2::geom_line(data = h[h$series == "Core", ], colour = BRIEF_INK,
                       linetype = "42", linewidth = 0.5) +
    ggplot2::geom_line(data = h[h$series == "Headline", ], colour = BRIEF_ACCENT,
                       linewidth = 0.7) +
    ggplot2::geom_text(data = ends,
                       ggplot2::aes(label = series),
                       colour = c(Headline = BRIEF_ACCENT, Core = BRIEF_INK)[ends$series],
                       hjust = -0.08, vjust = 0.5, size = 2.6) +
    ggplot2::scale_x_date(expand = ggplot2::expansion(mult = c(0.01, 0.16)),
                          date_labels = "%Y") +
    ggplot2::scale_y_continuous(labels = function(x) paste0(x, "%")) +
    ggplot2::labs(title = "Consumer inflation, y/y",
                  subtitle = "Headline and core; 3–6% band, 4,5% midpoint",
                  caption = source_caption("P0141", t$vintage[[1]]$retrieved_at)) +
    theme_brief()
}

#' Current-month y/y by COICOP division, horizontal bars.
chart_cpi_divisions <- function(t) {
  d <- t$divisions
  d$name <- factor(d$name, levels = rev(d$name))
  ggplot2::ggplot(d, ggplot2::aes(yy, name)) +
    ggplot2::geom_col(fill = BRIEF_ACCENT, width = 0.65) +
    ggplot2::geom_text(ggplot2::aes(label = format_za(yy, 1),
                                    hjust = ifelse(yy >= 0, -0.15, 1.15)),
                       colour = BRIEF_INK, size = 2.4) +
    ggplot2::geom_vline(xintercept = 0, colour = BRIEF_GREY, linewidth = 0.3) +
    ggplot2::scale_x_continuous(expand = ggplot2::expansion(mult = c(0.02, 0.12)),
                                labels = function(x) paste0(x, "%")) +
    ggplot2::labs(title = sprintf("Inflation by division, %s", t$label),
                  subtitle = "y/y, per cent",
                  caption = source_caption("P0141", t$vintage[[1]]$retrieved_at)) +
    theme_brief() +
    ggplot2::theme(panel.grid.major.y = ggplot2::element_blank(),
                   axis.text.y = ggplot2::element_text(colour = BRIEF_INK, size = 6.6))
}

#' Inflation breadth: share of CPI weight inflating above the midpoint.
chart_cpi_breadth <- function(t) {
  b <- t$breadth
  ggplot2::ggplot(b, ggplot2::aes(date, share)) +
    ggplot2::geom_hline(yintercept = 50, colour = BRIEF_GREY,
                        linetype = "dotted", linewidth = 0.35) +
    ggplot2::geom_line(colour = BRIEF_ACCENT, linewidth = 0.7) +
    ggplot2::scale_y_continuous(labels = function(x) paste0(x, "%"),
                                limits = c(0, 100)) +
    ggplot2::labs(title = "Inflation breadth",
                  subtitle = "Share of CPI weight with y/y inflation above the 4,5% midpoint",
                  caption = source_caption("P0141 (8-digit)", t$vintage[[1]]$retrieved_at)) +
    theme_brief()
}

#' PPI headline y/y with CPI y/y overlaid.
chart_ppi_vs_cpi <- function(t) {
  h <- t$history   # series: "PPI", "CPI"
  ends <- do.call(rbind, lapply(split(h, h$series), function(d) d[which.max(d$date), ]))
  ggplot2::ggplot(h, ggplot2::aes(date, yy, group = series)) +
    ggplot2::geom_hline(yintercept = 0, colour = BRIEF_GREY, linewidth = 0.3) +
    ggplot2::geom_line(data = h[h$series == "CPI", ], colour = BRIEF_INK,
                       linetype = "42", linewidth = 0.5) +
    ggplot2::geom_line(data = h[h$series == "PPI", ], colour = BRIEF_ACCENT,
                       linewidth = 0.7) +
    ggplot2::geom_text(data = ends, ggplot2::aes(label = series),
                       colour = c(PPI = BRIEF_ACCENT, CPI = BRIEF_INK)[ends$series],
                       hjust = -0.08, size = 2.6) +
    ggplot2::scale_x_date(expand = ggplot2::expansion(mult = c(0.01, 0.12)),
                          date_labels = "%Y") +
    ggplot2::scale_y_continuous(labels = function(x) paste0(x, "%")) +
    ggplot2::labs(title = "Producer vs consumer inflation, y/y",
                  subtitle = "PPI: final manufactured goods",
                  caption = source_caption("P0142.1; P0141", t$vintage[[1]]$retrieved_at)) +
    theme_brief()
}

#' GDP q/q (seasonally adjusted, not annualised) bars over three years.
chart_gdp_qq <- function(t) {
  h <- t$qq_history
  h$sign <- ifelse(h$qq >= 0, "pos", "neg")
  ggplot2::ggplot(h, ggplot2::aes(date, qq, fill = sign)) +
    ggplot2::geom_col(width = 60) +
    ggplot2::geom_hline(yintercept = 0, colour = BRIEF_GREY, linewidth = 0.3) +
    ggplot2::geom_text(ggplot2::aes(label = format_za(qq, 1),
                                    vjust = ifelse(qq >= 0, -0.4, 1.3)),
                       colour = BRIEF_INK, size = 2.3) +
    ggplot2::scale_fill_manual(values = c(pos = BRIEF_ACCENT, neg = BRIEF_GREY)) +
    ggplot2::scale_y_continuous(labels = function(x) paste0(x, "%"),
                                expand = ggplot2::expansion(mult = 0.18)) +
    ggplot2::scale_x_date(labels = function(d) sprintf("%dQ%d", lubridate::year(d),
                                                       lubridate::quarter(d))) +
    ggplot2::labs(title = "Real GDP growth, q/q",
                  subtitle = "Seasonally adjusted, constant 2015 prices, not annualised",
                  caption = source_caption("P0441, QRS1000", t$vintage[[1]]$retrieved_at)) +
    theme_brief()
}

#' GDP industry contributions to q/q growth in pp, horizontal.
chart_gdp_contributions <- function(t) {
  d <- t$contributions
  d <- d[order(d$pp), ]
  d$name <- factor(d$name, levels = d$name)
  ggplot2::ggplot(d, ggplot2::aes(pp, name)) +
    ggplot2::geom_col(ggplot2::aes(fill = pp >= 0), width = 0.65) +
    ggplot2::geom_text(ggplot2::aes(label = format_za(pp, 1),
                                    hjust = ifelse(pp >= 0, -0.2, 1.2)),
                       colour = BRIEF_INK, size = 2.4) +
    ggplot2::geom_vline(xintercept = 0, colour = BRIEF_GREY, linewidth = 0.3) +
    ggplot2::scale_fill_manual(values = c(`TRUE` = BRIEF_ACCENT, `FALSE` = BRIEF_GREY)) +
    ggplot2::scale_x_continuous(expand = ggplot2::expansion(mult = c(0.08, 0.14))) +
    ggplot2::labs(title = sprintf("Contributions to q/q growth, %s", t$label),
                  subtitle = "Percentage points, seasonally adjusted",
                  caption = source_caption("P0441", t$vintage[[1]]$retrieved_at)) +
    theme_brief() +
    ggplot2::theme(panel.grid.major.y = ggplot2::element_blank(),
                   axis.text.y = ggplot2::element_text(colour = BRIEF_INK, size = 6.6))
}

#' QLFS: LU1 and LU3 over five years. LU3 is not called "expanded
#' unemployment" anywhere: it is the nearest analogue, not identically defined.
chart_qlfs_rates <- function(t) {
  h <- t$rate_history
  ends <- do.call(rbind, lapply(split(h, h$series), function(d) d[which.max(d$date), ]))
  ggplot2::ggplot(h, ggplot2::aes(date, rate, group = series)) +
    ggplot2::geom_line(data = h[h$series == "LU3", ], colour = BRIEF_INK,
                       linetype = "42", linewidth = 0.5) +
    ggplot2::geom_line(data = h[h$series == "LU1", ], colour = BRIEF_ACCENT,
                       linewidth = 0.7) +
    ggplot2::geom_text(data = ends, ggplot2::aes(label = series),
                       colour = c(LU1 = BRIEF_ACCENT, LU3 = BRIEF_INK)[ends$series],
                       hjust = -0.15, size = 2.6) +
    ggplot2::scale_x_date(expand = ggplot2::expansion(mult = c(0.01, 0.1)),
                          date_labels = "%Y") +
    ggplot2::scale_y_continuous(labels = function(x) paste0(x, "%")) +
    ggplot2::labs(title = "Labour underutilisation",
                  subtitle = "LU1 (unemployment rate) and LU3 (unemployment + potential labour force)",
                  caption = source_caption("P0211", t$vintage[[1]]$retrieved_at)) +
    theme_brief()
}

#' QLFS: employment change by industry, thousands, horizontal bars.
chart_qlfs_employment <- function(t) {
  d <- t$industry_changes
  d <- d[order(d$change), ]
  d$name <- factor(d$name, levels = d$name)
  ggplot2::ggplot(d, ggplot2::aes(change, name)) +
    ggplot2::geom_col(ggplot2::aes(fill = change >= 0), width = 0.65) +
    ggplot2::geom_text(ggplot2::aes(label = format_za(change, 0),
                                    hjust = ifelse(change >= 0, -0.15, 1.15)),
                       colour = BRIEF_INK, size = 2.4) +
    ggplot2::geom_vline(xintercept = 0, colour = BRIEF_GREY, linewidth = 0.3) +
    ggplot2::scale_fill_manual(values = c(`TRUE` = BRIEF_ACCENT, `FALSE` = BRIEF_GREY)) +
    ggplot2::scale_x_continuous(expand = ggplot2::expansion(mult = c(0.1, 0.16))) +
    ggplot2::labs(title = sprintf("Employment change by industry, %s", t$label),
                  subtitle = "q/q, thousands",
                  caption = source_caption("P0211", t$vintage[[1]]$retrieved_at)) +
    theme_brief() +
    ggplot2::theme(panel.grid.major.y = ggplot2::element_blank(),
                   axis.text.y = ggplot2::element_text(colour = BRIEF_INK, size = 6.6))
}
