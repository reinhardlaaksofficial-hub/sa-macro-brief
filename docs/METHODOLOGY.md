# Methodology

Formal definitions for every computed statistic in the pipeline. One symbol,
one meaning, everywhere: code, charts, tables and prose all use the
definitions below.

## Growth rates

For an index or level series `I_t` at the series' own frequency:

- **m/m** — month on preceding month, per cent:
  `100 · (I_t / I_{t−1} − 1)`.
- **q/q** — quarter on preceding quarter, per cent, computed on **seasonally
  adjusted** series, **not annualised**: `100 · (I_t / I_{t−1} − 1)`.
  The GDP headline is q/q on `QRS1000` (constant 2015 prices, seasonally
  adjusted and annualised *levels*); the annualisation of the levels cancels
  in the ratio, and the growth rate is not annualised. This matches the
  release footnote's convention.
- **y/y** — versus the same period one year earlier, per cent:
  `100 · (I_t / I_{t−s} − 1)` with `s = 12` (monthly) or `4` (quarterly).
  GDP y/y is computed on `QRU1000` (constant prices, actual values):
  year-on-year comparisons belong on unadjusted data.
- **pp** — percentage points. Used for changes in a rate (the unemployment
  rate rose 0,4 pp, never "0,4%") and for contributions to growth. No second
  abbreviation (`ppt`, `% points`) appears anywhere.

## Headline definitions

- **CPI headline**: `CPS00000`, CPI headline for all urban areas,
  Dec 2024 = 100.
- **CPI core**: `CPS00014`, *CPI excluding food and non-alcoholic beverages,
  fuel and energy* (weight 74,53). Published directly by Stats SA; never
  reconstructed.
- **PPI headline**: `PPC30000`, PPI for final manufactured goods,
  Dec 2023 = 100.
- **GDP headline**: q/q growth from `QRS1000` as above. Q1 2026 = 0,5%.
- **Unemployment**: LU1 (the official unemployment rate) **and** LU3 (the
  combined rate of unemployment and the potential labour force) are always
  reported together. LU3 is *not* called the "expanded unemployment rate": it
  is the nearest analogue under the post-Q3:2025 framework but is not
  identically defined. Reporting only one misrepresents the South African
  labour market. The QLFS covers ages 15–64.

## The LU1–LU4 framework

From the 19th ICLS labour underutilisation framework as published in the
QLFS from Q3:2025:

- **LU1** — unemployment rate: unemployed / labour force.
- **LU2** — combined rate of unemployment and time-related underemployment.
- **LU3** — combined rate of unemployment and the potential labour force:
  (unemployed + potential labour force) / (labour force + potential labour
  force).
- **LU4** — composite measure: LU2's numerator plus the potential labour
  force over the extended labour force.

## Seasonal adjustment

Only Stats SA's published seasonally adjusted series are used; the pipeline
never runs its own seasonal adjustment. Every output states the attribution.
Where no seasonally adjusted series is published (CPI, PPI, QLFS levels),
quarter- or month-on-month comparisons are made on raw series and labelled
as such, or not made at all.

## Inflation breadth

From the 8-digit product file (the only CPI file with weights): for month `t`,

```
breadth_t = 100 · Σ w_i · 1[yy_{i,t} > 4,5] / Σ w_i
```

summing over products `i` whose y/y is computable at `t` (12 months of
history and a non-missing observation). Products without a computable y/y
leave both numerator and denominator — the share is of *measurable* weight,
and measured coverage is reported alongside (87,8% of weight in April 2025,
reflecting products new to the January 2025 basket). Stats SA does not
publish this series.

## CPI division contributions

Contribution of division `i` to headline y/y in month `t`, in pp:

```
pp_i = (w_i / 100) · yy_{i,t} · (I_{i,t−12} / I_{head,t−12})
```

where `w_i` is the division's weight (the sum of its 8-digit product
weights, Dec 2024 basket) and the final ratio re-prices that weight to the
comparison month — the term that makes contributions sum to the headline.
Two reconciliations are asserted on every run:

1. `Σ pp_i` equals headline y/y within 0,15 pp (publication rounding across
   13 divisions on 1-decimal index levels);
2. each division matches the release PDF's Table C within 0,1 pp, whenever
   the release PDF is cached. Stats SA folds divisions contributing less
   than ~0,05 pp into a "Residual" line; those have no published comparator.

July 2026: computed sum 4,29 vs headline 4,26; every published division
within 0,05 pp of Table C.

## GDP industry contributions

Contribution of industry `i` to q/q growth, in pp, on seasonally adjusted
annualised constant-2015-price levels:

```
pp_i = 100 · (X_{i,t} − X_{i,t−1}) / GDP_{t−1}
```

for the ten industries plus taxes less subsidies on products (`QRS1012`).
The sum must reconcile to headline q/q within 0,06 pp or the run aborts
(Q1 2026: 0,545 vs 0,545 — exact). Known-good anchors: finance 0,2 pp,
manufacturing −0,1 pp.

## Revision policy

Every download is stamped with its retrieval time (the **vintage**) in a
sidecar file. On every run, current values of key series are snapshotted to
`data/vintages/{release}.csv` and diffed against the latest prior snapshot;
any changed historical observation is flagged in the output footer as
"revised from X to Y", never silently absorbed. A `_v2`/`_v3` suffix on a
published filename is treated as a revision signal and logged. GDP revision
tracking accumulates the q/q growth implied by each vintage and reports the
mean absolute movement of first prints once two or more vintages exist.

## Break handling

`config/series_breaks.yaml` records: the CPI rebase and reweight
(Dec 2024 = 100, January 2025 basket), the PPI rebase (Dec 2023 = 100) and
2013 series rebuild, the QLFS Q3:2025 ICLS revision (informality
definitions changed materially — informality comparisons are suppressed
before Q3:2025, not computed; headline employment and unemployment are
continuous), and the pending GDP rebasing to a 2022 base year. The GDP
reader loads the `Concordance (Q)` sheet (Stats SA → SARB → old Stats SA
codes) on every run so the rebasing can be absorbed by mapping, not
re-coding.

## Missing data

Unparseable or absent values become `NA` and print as "not available".
Nothing is interpolated or fabricated. Failures are recorded in
`docs/OPEN_QUESTIONS.md` and the run continues with the remaining fields
where possible; integrity-check failures abort with a named check.
