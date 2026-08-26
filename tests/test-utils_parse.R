test_that("parse_period handles all three Stats SA formats and CLI forms", {
  p <- parse_period(c("MO012008", "MO072026", "M200801", "199301", "202601",
                      "2026-07", "2026Q1", "garbage", "H03"))
  expect_equal(p$period, c("2008-01", "2026-07", "2008-01", "1993Q1", "2026Q1",
                           "2026-07", "2026Q1", NA, NA))
  expect_equal(p$freq, c("monthly", "monthly", "monthly", "quarterly", "quarterly",
                         "monthly", "quarterly", NA, NA))
  expect_equal(p$date[2], as.Date("2026-07-01"))
  expect_equal(p$date[5], as.Date("2026-01-01"))
})

test_that("parse_period rejects impossible months and quarters", {
  p <- parse_period(c("MO132008", "202605", "2026Q5"))
  expect_true(all(is.na(p$period)))
})

test_that("parse_period_one errors on unrecognised input", {
  expect_error(parse_period_one("July 2026"), "Unrecognised period")
})

test_that("parse_number handles Stats SA numeric conventions", {
  expect_equal(parse_number("107.7"), 107.7)
  expect_equal(parse_number("33,6"), 33.6)
  expect_equal(parse_number("41 822"), 41822)
  expect_equal(parse_number("4 772 090,6"), 4772090.6)
  expect_equal(parse_number("-0,1"), -0.1)
  expect_equal(parse_number("−0,1"), -0.1)  # unicode minus
  expect_true(is.na(parse_number("..")))
  expect_true(is.na(parse_number("")))
  expect_true(is.na(parse_number("-")))
  expect_true(is.na(parse_number("text")))
  # blanks map to NA, never zero
  expect_false(identical(parse_number(""), 0))
})

test_that("period arithmetic works in both frequencies", {
  expect_equal(period_next("2026-07"), "2026-08")
  expect_equal(period_next("2025-12"), "2026-01")
  expect_equal(period_next("2026Q1"), "2026Q2")
  expect_equal(period_next("2025Q4"), "2026Q1")
  expect_equal(period_lag("2026-07", 12), "2025-07")
  expect_equal(period_lag("2026Q1", 1), "2025Q4")
  expect_equal(period_lag("2026Q1", 4), "2025Q1")
})

test_that("period_label renders human labels", {
  expect_equal(period_label("2026Q1"), "Q1 2026")
  expect_match(period_label("2026-07"), "2026")
})

test_that("format_za renders decimal commas and space thousands", {
  expect_equal(format_za(4772090.6), "4 772 090,6")
  expect_equal(format_za(0.5), "0,5")
  expect_equal(format_za(NA), "not available")
})
