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

**A blocked HTML page is not a blocked site.** The first build concluded the
site was unreachable after testing only the `?page_id=` publication page, and
sourced everything from the Internet Archive. That was wrong: the static data
files serve normally to the same client. The lesson worth keeping is that a
negative result about *one URL shape* must not be generalised to a host —
especially when the generalisation quietly defeats the tool's whole purpose.
The fetch layer now proves the direct path on every run and records per-file
provenance so this cannot be hand-waved again.

**Probe-verified discovery instead of a mirror workaround.** Where HTML
discovery is challenged, candidate filenames are HEAD-probed against the live
server and only a confirmed 200 is used. This is deliberately not the
"construct a filename" approach the brief forbids: construction assumes,
probing verifies, and supersession surfaces as a 404 on the old name rather
than a stale download. Answering or bypassing the bot check was rejected
outright; so was serving *discovery* from a mirror, since stale links are
worse than no links.

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

## Stage 6 — analytics beyond arithmetic

**Breadth denominator.** The share of CPI weight inflating above the 4,5%
midpoint is computed over *measurable* weight: products whose y/y cannot be
computed in a month (history starts later) leave both numerator and
denominator. The alternative — treating unmeasurable products as
below-midpoint — would bias breadth downward exactly when the basket is
refreshed. Coverage is reported alongside the share (87,8% in April 2025,
reflecting products new to the Jan 2025 basket).

**Contribution formula.** Division contribution to headline y/y is
(w_i/100)·yy_i·(I_i,t−12/I_head,t−12): the index-ratio factor re-prices the
Dec 2024 weight to the comparison month, which is what makes contributions
sum to the headline (gap 0,03 pp in July 2026). Reconciliation runs twice:
internally against the computed headline (abort beyond 0,15 pp) and against
the release PDF's Table C when cached (abort beyond 0,1 pp on any division).
On July 2026 every published division agrees within 0,05 pp; Stats SA folds
divisions smaller than ~0,05 pp into a "Residual" line, which is why two
computed divisions have no published counterpart.

**GDP revision tracking.** First-print movement is computed from the
accumulated vintage store rather than a separate ledger, so it needs no extra
bookkeeping on release day; with a single vintage cached it reports nothing
rather than fabricating a history.

**Quarto binary.** The machine has no standalone Quarto; the pipeline uses the
Quarto 1.8.25 bundled with RStudio via the `QUARTO_PATH` environment variable
set in `sa-brief`. Installing a second Quarto via Homebrew was rejected as
redundant. TinyTeX is installed once via `tinytex::install_tinytex()` for PDF
output, per the brief.
