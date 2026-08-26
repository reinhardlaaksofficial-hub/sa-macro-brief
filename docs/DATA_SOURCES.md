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

## Discovery ladder and the HTML challenge

Stats SA's Imperva layer challenges HTML requests from some networks — every
`?page_id=` page, the timeseries index, directory listings — while serving the
static data files (`.xlsx`, `.zip`, `.pdf`) to the same client, with the same
descriptive User-Agent, without challenge. Measured on the build machine:
data files 200, HTML challenged on every attempt.

The fetcher therefore discovers artefacts in three rungs, always live first:

1. **Publication page** — scraped, links taken verbatim. Canonical, and the
   method the brief specifies. Primary on every run.
2. **Probe-verified discovery** — the small set of filename variants actually
   observed in Stats SA's published links is HEAD-probed against the live
   server, newest correction first, and only a path the server confirms with
   a 200 is used. Nothing is assumed: a wrong guess is a 404, not a corrupt
   file, and supersession is detected (for GDP Q1 2026 the server returns 200
   for `_v2` and 404 for the un-suffixed name).
3. **Internet Archive mirror** — last resort, file bytes only.

Discovery is never served from a mirror or from a cached mirrored page: a
stale publication page yields last month's links, which is worse than none.
The challenge page is detected so it can never be mistaken for content, and
is never answered or bypassed. Each artefact's vintage sidecar records both
`source` (statssa / wayback) and `discovery` (publication_page /
probe_verified), so provenance is auditable per file.

## Limitations

- The QLFS is parsed from PDF text; the parser is landmark-based and
  asserts accounting identities after every parse, but a substantial layout
  redesign by Stats SA would require re-anchoring.
- Probe-verified discovery depends on a list of naming variants observed in
  Stats SA's own links; a genuinely new shape fails loudly, listing the
  candidates it probed, rather than silently fetching the wrong file.
- LU3 exists only from Q3:2025; long LU histories are structurally
  unavailable and accumulate release by release.
