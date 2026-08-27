# Notices

## Scope of the MIT licence

[`LICENSE`](LICENSE) covers **the source code in this repository only**.

## Statistics South Africa data

The statistical data this software retrieves is published by Statistics South
Africa and is **not** covered by the MIT licence. Per Stats SA's terms:

> Users may apply the information as they wish, provided they acknowledge
> Stats SA as the source of the basic data, and specify that the relevant
> application and analysis result from their own processing of the data.

Every briefing this software generates carries that acknowledgement in its
footer, together with the source publication code and the retrieval
timestamp.

**No Stats SA release files are redistributed here.** Two categories of
derived material are committed:

- `tests/testthat/fixtures/` — small derived extracts (a few series, a
  trimmed period range, and page text) used solely to verify the parsers
  offline, so that cloning this repository never means downloading from a
  government statistics server. Regenerate with
  `Rscript data-raw/make-fixtures.R`.
- `briefs/` and `docs/examples/` — briefing notes produced by this software,
  which are our own processing of the basic data and carry the
  acknowledgement above.

If you redistribute anything derived from those files, carry the
acknowledgement with it.

## Dependencies

This project does not vendor or redistribute any R package. Dependencies are
resolved at install time by `renv` from CRAN, and each remains under its own
licence. Of the 20 packages used, 19 are permissive (MIT, BSD or Apache);
`optparse` (the command-line argument parser) is GPL (>= 2). Because this
repository distributes only its own source
code and never ships those packages, the code here is offered under MIT; a
combined *binary distribution* that bundled GPL dependencies would need to
respect the GPL terms of those components.

Run `Rscript -e 'renv::restore()'` to install them, and see each package's
own DESCRIPTION for its licence.
