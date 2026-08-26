# Open questions and recorded deviations

Where the brief and the actual files disagreed, or a fact could not be
verified, the chosen interpretation is recorded here with the evidence.

## Unresolved at project start

- **`SCH` ids for PPI and QLFS** are unknown; the fetch layer discovers the
  current release by scraping the publications index (`discover_sch()`), taking
  the highest SCH linked for the PPN. **`SCH` is per-release, not
  per-publication**: SCH=74468 is specifically the June 2026 CPI release
  (its page stamps "Publication date & time: 22 July 2026 @ 10:00" and links
  the `(202606)` zips), and SCH=74518 is the Q1 2026 GDP release. Each new
  release gets a new SCH.

## Stage 2 — fetching, recorded 2026-08-26

- **Imperva bot protection blocks non-browser clients on this network.**
  `www.statssa.gov.za` served an Incapsula/Imperva challenge (a
  click-the-checkbox human check) to every client available in this
  environment; completing such checks by automation is off-limits, so the
  live site could not be fetched directly. The brief (§3.1) says the pages
  were verified by its author, so the block is likely network/IP-dependent —
  the pipeline's direct path should work from a trusted network. `fetch_url()`
  therefore tries Stats SA first, detects the challenge page (never mistaking
  it for content), and falls back to the Internet Archive's copy of the same
  URL, recording `source: wayback` in the vintage sidecar. All cached inputs
  in `data-raw/` were obtained this way (four via Save Page Now requests);
  every downloaded file's contents were verified against the brief's
  ground-truth values before use.
- **CPI 8-digit file: only the April 2025 vintage (`202504`) is archived.**
  The `202607` vintage was requested via Save Page Now but had not been
  captured by the Internet Archive at build time (requests returned 429
  rate-limits). Consequence: product weights (static within the 2025 basket)
  are available and correct, but the inflation-breadth series ends April 2025
  instead of July 2026. `fetch_release()` prefers the exact vintage and falls
  back to the newest cached 8-digit file for weights. When run on a network
  the site trusts, the current file is fetched and breadth extends
  automatically. A failing test named `breadth series reaches the CPI
  reference month (needs 202607 8-digit vintage)` marks the gap.
## Stage 5 — readers for PPI, GDP, QLFS

- **The GDP Q1 2026 workbook has a mislabelled period column.** In sheet
  `Quarterly` of `GDP P0441 - GDP Time series Q1 2026_v2.xlsx`, the header row
  contains `201803` twice and no `201804` (columns 113-114 of the sheet).
  The brief (§4) does not mention this. Evidence that the second `201803` is
  really 2018Q4: agriculture's current-price actual (`QNU1001`) shows its
  regular Q4 seasonal trough there (13 866,6, vs 16 485,6 in 2017Q4 and
  13 595,5 in 2019Q4). `read_hcode()` repairs exactly this pattern — a
  duplicated column whose immediate successor period is missing — logs the
  repair, and still aborts on any other duplicate. Chosen over dropping the
  column (which would silently delete a quarter of history).
- **QLFS LU-rate history is short by construction.** The brief asks for LU1
  and LU3 over five years, but LU3 has existed only since the Q3:2025
  questionnaire revision, and the QLFS is published as PDF (each release
  carries three period columns). The pipeline accumulates rate observations
  from every parsed release into `data/vintages/qlfs_rates.csv`, so the chart
  lengthens as releases (or cached back-issues) are processed. With one cached
  PDF the chart shows Q2 2025, Q1 2026 and Q2 2026.
- **CPI reference period lags its release**: June 2026 CPI was published
  22 July 2026; the July 2026 CPI files (`202607`) appeared in August. The
  `release_calendar.yaml` known-dates list records only page-verified dates.
