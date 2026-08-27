# Notices

## Scope of the licence

[`LICENSE`](LICENSE) is the **PolyForm Noncommercial License 1.0.0**, and it
covers **the source code in this repository only**.

Permitted without asking: personal study, research and experimentation,
hobby and amateur use, and use by charities, educational institutions, public
research bodies and government. **Commercial use is not granted** by this
licence — including internal use by a for-profit company. If you want to use
this commercially, contact the author for a separate licence.

This licence is deliberately not an OSI "open source" licence: it restricts
the field of use, which the Open Source Definition does not allow.

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
code and never ships those packages, its own terms apply to its own code
alone. Note that a combined *binary distribution* bundling GPL dependencies
would have to respect those components' GPL terms, which are incompatible
with a noncommercial restriction — so do not ship this as a bundled binary
containing `optparse`.

Run `Rscript -e 'renv::restore()'` to install them, and see each package's
own DESCRIPTION for its licence.
