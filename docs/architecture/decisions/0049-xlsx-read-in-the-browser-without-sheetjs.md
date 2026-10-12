# ADR-0049: Excel workbooks are read in the browser without SheetJS

**Status:** Accepted (builder decision)
**Date:** 2026-09-23
**Source:** builder decision under plan Section 9.3, feature C-19; departed from plan Section 4.9
("client-side parsing with SheetJS") and Section 9 (SheetJS as the one pre-approved
third-party script) as they then read. Both sections now cite this ADR.

## Context

C-19 adds .xlsx upload to the import wizard. The plan names SheetJS for it and pre-approves it
as a vetted static resource.

The SheetJS build on the public npm registry (`xlsx` 0.18.5) has not been updated since 2022
and carries two published advisories: prototype pollution when reading a crafted file
(CVE-2023-30533) and a regular-expression denial of service (CVE-2024-22363). The fixed
releases are published only on the vendor's own CDN, outside npm, so the repository's
dependency tooling (`npm audit`, Dependabot) cannot see or update them. Vendoring one means a
hand-copied minified file of several hundred kilobytes that nobody reviews line by line, and a
manual watch on a site the tooling does not follow. The file an import reads is by nature a
file from outside the organization.

The import needs very little of what SheetJS does: the values of the first sheet, as text,
from the current .xlsx format. It does not write workbooks, read formatting, evaluate formulas
or read the legacy binary .xls format.

## Decision

**The wizard reads .xlsx itself, in `lwc/importWizard/xlsx.js`, with no third-party code.**

- An .xlsx file is a zip of XML. The reader walks the zip's central directory, inflates the
  parts it needs with the browser's own `DecompressionStream('deflate-raw')`, and reads the XML
  with `DOMParser`. It reads the workbook, its relationships, the shared strings, the styles
  (only to tell a date from a number) and the first sheet.
- It returns the same rows of text the CSV reader returns, so mapping, staging, dry run and
  commit are unchanged. A formula gives its last saved value; a date gives `YYYY-MM-DD`, with
  the time when there is one, in either of Excel's date systems.
- A browser without `DecompressionStream`, a file that is not a workbook, or a zip feature
  the reader does not handle (ZIP64, encryption) is refused with a sentence that says to save
  the sheet as CSV and upload that. Nothing is guessed.
- A workbook too large to read in the browser is refused the same way: a part whose declared
  or inflated size is over 100 MB, a row past 500,000 or a column past 1,000. The declared
  size is read from the central directory, so a small file claiming a huge sheet is refused
  before it is inflated.
- The reader is covered by Jest tests that build workbooks in the test, including a skipped
  row and column, rich text, inline strings, booleans, both date systems and stored (not
  compressed) parts.

## Alternatives considered

- **SheetJS from npm, as the plan says.** Rejected: the npm build is frozen at a version with
  open advisories, and the fixed ones are not on npm.
- **SheetJS vendored from the vendor's CDN as a static resource.** Rejected for now: a large
  minified file outside dependency tooling, updated by hand, to use a small part of it. It
  remains the fallback if a later feature needs formatting, several sheets or .xls.
- **Another npm library.** Rejected: the maintained ones are either large or depend on a zip
  library as well, which moves the same problem rather than removing it.
- **CSV only.** Rejected: the plan commits to XLSX in v0.5, and "save as CSV" is a step Maria
  gets wrong (encoding, dates turned into text).

## Consequences

- No third-party script ships in the wizard, and plan Section 9's pre-approval of SheetJS is
  unused. The plan owner has since edited Sections 4.9 and 9 to match.
- The reader is BarnCRM's to maintain. Its scope is fixed by this ADR: first sheet,
  values only, .xlsx only. A request for more reopens the choice above rather than growing it.
- Legacy .xls files and password-protected workbooks are not read; the message says to save
  as CSV or .xlsx.
