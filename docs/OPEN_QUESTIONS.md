# Open questions and recorded deviations

Where the brief and the actual files disagreed, or a fact could not be
verified, the chosen interpretation is recorded here with the evidence.

## Correction — 2026-08-26, after the first build

An earlier revision of this file claimed Stats SA had "blocked this machine"
and that the pipeline had to source its data from the Internet Archive. **That
was wrong, and it was wrong in the way that mattered most.** Only the site's
HTML surfaces are challenged by its Imperva layer; the static data files were
reachable from this machine the entire time. The original conclusion came from
testing exactly one URL shape — the `?page_id=1854` publication page — and
generalising from it without ever requesting an `.xlsx`, `.zip` or `.pdf`
directly. Measured behaviour, same machine, same network, same descriptive
User-Agent:

| URL shape | Result |
|---|---|
| `/publications/P0441/….xlsx` | **200**, 4,7 MB, correct content type |
| `/timeseriesdata/Excel/….zip` | **200**, correct content type |
| `/publications/P0211/….pdf` | **200** |
| `?page_id=1854&PPN=…` (publication page) | Imperva challenge, every attempt |
| `?page_id=1847` (timeseries index) | Imperva challenge |
| `/timeseriesdata/Excel/` (directory listing) | Imperva challenge |

So automated release-day fetching works directly against Stats SA. What does
not work from this network is **HTML link discovery**, which is a narrower
problem than "the site is blocked" and has a proper fix (rung B below) rather
than a mirror workaround. All four briefs are now built from files fetched
live from statssa.gov.za in this session; `source: statssa` on every artefact.

## Final run summary — 2026-08-26

**Passed.**
- `testthat::test_dir("tests")`: **147 passing, 0 failing, 0 skipped** —
  parsers, discovery, fetch layer, all four readers, analytics and accounting
  identities. Includes every known-good release value in the brief (CPI 107,7 /
  4,3 / 0,2 / core 4,2; PPI 110,3 / 7,5 / −0,1; GDP 4 772 090,6 / 0,5 / 0,4 /
  finance 0,2 pp / manufacturing −0,1 pp; QLFS 33,6 / 43,8 / 39,6 / 59,6 /
  16 739) and a live probe that resolves the GDP artefact to its `_v2`
  correction against the running server.
- **All four releases fetched live from statssa.gov.za** with
  `--refresh` after deleting `data-raw/` entirely: every artefact's vintage
  sidecar records `source: statssa`, `discovery: probe_verified`. No mirror
  used anywhere.
- The CPI release PDF is fetched automatically, so the Table C
  reconciliation runs unattended: 11 published divisions matched, worst
  difference 0,052 pp.
- Inflation breadth now runs to the reference month (41,6% of CPI weight
  above the 4,5% midpoint in July 2026).
- Idempotence: repeat runs produce byte-identical PDFs.

**Known limitations, stated plainly.**
1. **HTML link discovery is unavailable from this network.** Rung A (scrape
   the publication page, take links verbatim — the brief's canonical method)
   runs first on every invocation and works wherever the site's protection
   does not challenge the client. Where it is challenged, the run falls to
   rung B, probe-verified discovery, and logs that it did so. Rung B is not
   blind filename construction: each candidate is HEAD-probed and only a
   filename the server confirms is used, which is why it correctly selects
   `GDP … Q1 2026_v2.xlsx` while the un-suffixed name returns 404.
2. **Rung B's candidate list needs maintenance if Stats SA invents a new
   naming variant.** Every pattern in `candidate_paths()` is one observed in
   Stats SA's own published links. A genuinely new shape would fail loudly
   with the probed candidates listed in the error, not silently.
3. The QLFS parser is landmark-based over PDF text and would need
   re-anchoring if Stats SA redesigns Table A or B.
4. LU3 exists only from Q3:2025, so its chart history accumulates release by
   release rather than starting five years back.

## Unresolved at project start

- **`SCH` ids for PPI and QLFS** are unknown; the fetch layer discovers the
  current release by scraping the publications index (`discover_sch()`), taking
  the highest SCH linked for the PPN. **`SCH` is per-release, not
  per-publication**: SCH=74468 is specifically the June 2026 CPI release
  (its page stamps "Publication date & time: 22 July 2026 @ 10:00" and links
  the `(202606)` zips), and SCH=74518 is the Q1 2026 GDP release. Each new
  release gets a new SCH.

## Stage 2 — fetching, recorded 2026-08-26 (revised after the correction above)

- **What is actually blocked.** `www.statssa.gov.za` serves an
  Incapsula/Imperva challenge to HTML requests from this network — publication
  pages, the timeseries index, directory listings — while serving `.xlsx`,
  `.zip` and `.pdf` to the same client, same User-Agent, without challenge.
  The challenge is never answered, bypassed or worked around; it is detected
  (`is_challenge_page()`) so a challenge page can never be mistaken for
  content, and discovery falls to a rung that does not need HTML.
- **Discovery ladder.** Rung A scrapes the publication page and takes links
  verbatim (the brief's §3.1 method, primary on every run). Rung B probes the
  observed filename variants with HEAD requests and uses only what the server
  confirms — this is what keeps release-day automation working here. Rung C,
  the Internet Archive mirror, is last resort and applies to file bytes only:
  **discovery is never served from a mirror**, because a stale publication
  page yields last month's links, which is worse than no links. That rule is
  enforced by `allow_mirror = FALSE` on discovery fetches and by refusing to
  reuse a cached discovery page whose vintage says it came from a mirror.
- **`_v2`/`_v3` handling under probing.** Corrections are probed
  highest-version-first, so the current file wins automatically, and a `_v3`
  or higher logs a revision signal. This is verified against live data: for
  GDP Q1 2026 the server returns 200 for `_v2` and **404 for the un-suffixed
  name**, which is exactly the failure mode the brief warns about, caught by
  the server rather than assumed.
- **CPI 8-digit vintage.** Resolved. The `202607` file downloads directly from
  Stats SA, so weights and the inflation-breadth series both run to the July
  2026 reference month. The earlier claim that only a `202504` archive copy
  was obtainable was a consequence of the mistaken "site is blocked"
  conclusion, not a real constraint.

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
