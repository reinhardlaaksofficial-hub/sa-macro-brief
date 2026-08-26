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

## Stage 4 — transform, charts, CPI brief end-to-end

**Reproducible PDFs.** Idempotence ("two runs, same period, byte-identical
output") is achieved by pinning `SOURCE_DATE_EPOCH` to the data vintage, a
fixed raster device (ragg at fixed size/dpi), and deriving every printed
timestamp from the vintage sidecar rather than the wall clock. Verified by
hashing two consecutive runs. The alternative — accepting nondeterministic
PDF creation dates — was rejected because it makes revision diffs noisy.

**One accent colour vs two-series charts.** The house style allows one accent,
but headline-vs-core and PPI-vs-CPI need two series. Comparison series wear
dark ink with a dashed linetype and a direct end label, so identity never
rides on hue alone (also the colour-vision-deficiency-safe choice; a teal/grey
hue pair failed a CVD-separation check). A second accent hue was rejected.

**Revision flagging.** Every run snapshots key-series values into
`data/vintages/{release}.csv` and diffs against the latest prior snapshot;
changed historical observations are reported in the PDF footer as
"revised from X to Y". Storing only changed observations keeps the store
small while preserving each distinct vintage.

**South African number style in output.** Prose, tables and chart labels use
decimal commas and thin-space thousands (matching Stats SA releases); code and
intermediate data keep R's decimal points. The mixed style in early drafts was
rejected for consistency with §6's one-symbol-one-meaning rule.

## Stage 5 — PPI, GDP, QLFS

**GDP y/y convention.** The headline is q/q seasonally adjusted, not
annualised, from `QRS1000` (per §6). The supplementary y/y figure is computed
from `QRU1000` (constant prices, actual values) because year-on-year
comparisons belong on unadjusted data — computing y/y on seasonally adjusted
levels would double-filter the seasonality.

**GDP contributions.** Contribution of industry i is
100·ΔX_i/GDP_{t-1} on seasonally adjusted annualised constant-price levels
(the annualisation scalar cancels). Industries plus taxes-less-subsidies must
reconcile to the headline within 0,06 pp or the run aborts; on Q1 2026 the
sum matches the headline exactly (0,545 vs 0,545).

**Repairing vs rejecting the mislabelled GDP column.** A duplicated `201803`
header with no `201804` is repaired positionally (with a logged message)
because the evidence is decisive and dropping it would delete 2018Q4 from
every series; any duplicate that does not match this exact pattern still
aborts. See OPEN_QUESTIONS.md for the evidence.

**QLFS parsing strategy.** Row labels are matched from a fixed list in
published order rather than inferred, because Table A's blocks change meaning
by position (levels in thousands, rates in %, changes in pp despite the %
header). Wrapped labels (LU2/LU3) are handled by taking the numeric line
that follows a number-free label line. Identities (employed + unemployed =
labour force; labour force + outside = working-age population) are asserted
with a 3-thousand rounding tolerance before any output is produced.

**Quarto binary.** The machine has no standalone Quarto; the pipeline uses the
Quarto 1.8.25 bundled with RStudio via the `QUARTO_PATH` environment variable
set in `sa-brief`. Installing a second Quarto via Homebrew was rejected as
redundant. TinyTeX is installed once via `tinytex::install_tinytex()` for PDF
output, per the brief.
