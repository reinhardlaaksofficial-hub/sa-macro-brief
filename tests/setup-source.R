# Sourced automatically by testthat::test_dir("tests").
# Loads every function under R/ so tests run against the working tree.
proj_root <- normalizePath(file.path(testthat::test_path(), ".."), mustWork = TRUE)
for (f in sort(list.files(file.path(proj_root, "R"), pattern = "\\.R$", full.names = TRUE))) {
  source(f, local = FALSE)
}
fixture_path <- function(...) file.path(proj_root, "tests", "testthat", "fixtures", ...)
