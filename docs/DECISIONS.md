# Decision log

Two or three sentences per stage on the design decision made and the
alternative rejected. Economic-definition, seasonality and data-quality
judgement calls are surfaced here rather than buried in code.

## Stage 1 — skeleton, parsing, configuration

**Test layout.** The finish-line check is `testthat::test_dir("tests")`, which
does not recurse, while the prescribed layout keeps fixtures in
`tests/testthat/fixtures/`. Test files therefore live directly in `tests/`
(with `setup-source.R` loading `R/`), and fixtures stay in
`tests/testthat/fixtures/` — satisfying both constraints literally. The
conventional `tests/testthat/` placement was rejected because it would make
the specified invocation fail.

**One `parse_period()` for five formats.** The three file formats (`MO`+MMYYYY,
`M`+YYYYMM, YYYYQQ) and the two CLI forms (`YYYY-MM`, `YYYYQn`) are handled by
one vectorised function returning `NA` for unrecognised tokens rather than
erroring. Readers decide whether a stray column is fatal; a hard error inside
the parser would make every reader fragile to harmless junk columns.

**Numbers: blanks and `..` map to `NA`, never zero.** `parse_number()` treats
decimal commas as decimal separators (PDF convention) and strips spaces inside
numeric tokens (thousands separators) before conversion. Where a token has
both comma and point, the comma is treated as a thousands separator — that
combination only appears in derived exports, never in Stats SA originals.

## Stage 2 — fetch layer

**Mirror fallback over challenge evasion.** When Stats SA's Imperva layer
challenges a client, the fetcher does not try to defeat it (no cookie
transplants, no header spoofing). It falls back to the Internet Archive's
copy of the identical URL and records the source in the vintage metadata, so
provenance is never silently laundered. The alternative — automating the
"verify you are human" check — was rejected outright.

**Cache-first release fetching.** `fetch_release()` looks for a cached
artefact matching the release pattern and period tag before touching the
network, making release-day re-runs offline-capable and idempotent; `--refresh`
bypasses the cache. Matching artefacts by regex against *scraped* filenames
(never constructing them) is what survives the `_v2`/`_v3` re-versioning and
the inconsistent spacing Stats SA uses.

**SCH discovery.** SCH proved to be a per-release schedule id, so PPI and QLFS
ids are discovered at run time as the highest SCH on the publication index for
the PPN, rather than pinned in config where they would go stale monthly.

**Quarto binary.** The machine has no standalone Quarto; the pipeline uses the
Quarto 1.8.25 bundled with RStudio via the `QUARTO_PATH` environment variable
set in `sa-brief`. Installing a second Quarto via Homebrew was rejected as
redundant. TinyTeX is installed once via `tinytex::install_tinytex()` for PDF
output, per the brief.
