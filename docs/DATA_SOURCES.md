# Data sources

All basic data: Statistics South Africa (www.statssa.gov.za). Users may apply
the information as they wish, provided they acknowledge Stats SA as the source
of the basic data, and specify that the relevant application and analysis
result from their own processing of the data.

## Entry points

Publication pages (canonical, per release):

```
https://www.statssa.gov.za/?page_id=1854&PPN={PPN}&SCH={SCH}
```

`SCH` is a per-release schedule id: each release of a publication gets a new
one, so current ids are discovered at run time from the publication index
rather than configured. The page lists every artefact (main PDF, press
release, fact sheets, spreadsheets) plus the publication date and time.
**Artefact filenames are scraped, never constructed** — releases get
re-versioned (`_v2`, `_v3`) after corrections and spacing is inconsistent.

| Release | PPN | Frequency | Primary format | Embargo (SAST) |
|---|---|---|---|---|
| Consumer Price Index | P0141 | monthly | Excel (zipped) | 10:00 |
| Producer Price Index | P0142.1 | monthly | Excel (zipped) | 11:30 |
| Gross Domestic Product | P0441 | quarterly | Excel | 11:00–11:30 |
| Quarterly Labour Force Survey | P0211 | quarterly | **PDF only** | 11:30 |

Long-history time series (CPI, PPI) are zipped Excel files under
`/timeseriesdata/Excel/`, indexed at `?page_id=1847`.

## Files used per brief

- **CPI**: `P0141 - CPI(COICOP) from Jan 2008 (YYYYMM).zip` (789 series,
  H-code layout, index levels only) and `P0141 - CPI(5 and 8 digit) from
  Jan 2017 (YYYYMM).zip` (391 products, named columns, the only file with
  weights and Stats SA's old-code concordance); the monthly release PDF
  (`P0141MonthYYYY.pdf`) for Table C reconciliation.
- **PPI**: `P0142.1 PPI New series from 2013(YYYYMM).zip` (76 series; note
  the missing space before the parenthesis is Stats SA's own).
- **GDP**: `GDP P0441 - GDP Time series Qn YYYY[_vN].xlsx`, sheets
  `Quarterly` and `Concordance (Q)` (note some sheet names carry trailing
  spaces).
- **QLFS**: `P0211{N}{ordinal}Quarter{YYYY}.pdf`, Tables A and B.

## Fetch etiquette

Descriptive User-Agent with a contact address; at least one second between
requests; exponential backoff; never parallelised against the government
server. Every download is cached in `data-raw/` with a `.vintage.yaml`
sidecar recording URL, retrieval timestamp and source; cached content is
never re-fetched unless `--refresh` is passed. After every download the
period inside the file is asserted against the period requested.

## Mirror fallback

`www.statssa.gov.za` sits behind Imperva bot protection which, on some
networks, challenges non-browser clients. The fetcher detects the challenge
page (it is never mistaken for content), does not attempt to defeat it, and
falls back to the Internet Archive's copy of the identical URL
(`web.archive.org/web/<year>if_/<url>`), recording `source: wayback` in the
vintage sidecar and in the PDF footer. The cached inputs in this repository
were obtained that way; on a network the site trusts, the direct path is
used and nothing else changes. See `docs/OPEN_QUESTIONS.md`.

## Limitations

- The QLFS is parsed from PDF text; the parser is landmark-based and
  asserts accounting identities after every parse, but a substantial layout
  redesign by Stats SA would require re-anchoring.
- The 8-digit CPI file's archived vintage lags the current month until the
  live site is reachable (affects the breadth series' endpoint only).
- LU3 exists only from Q3:2025; long LU histories are structurally
  unavailable and accumulate release by release.
