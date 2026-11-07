# ADR-NEXT: Radius Find measures from a shipped postal code table, with no outside geocoding

**Status:** Accepted (builder decision)
**Date:** 2026-11-06
**Source:** plan D-157 (research proposal 10, approved 2026-10-31), feature C-69, release 1.1;
builds on ADR-0047 and ADR-0078 (the Find query document)

## Context

Find (C-34, C-36) builds queries only from a document that `QueryCompiler` checks against the
running user's describe, with every value bound and the query run in user mode (R-SQ1, R-SQ2).
C-69 adds "within N miles of a postal code or address". Salesforce stores a geocode (latitude
and longitude) on standard addresses when Data Integration Rules geocoding is on, and SOQL
`DISTANCE` compares a stored geocode to a point. The point has to come from somewhere: the plan
rules out a geocoding service ("no outside geocoding"), the architecture allows no outside
callout for this, and a typed street address cannot be turned into a point without one.

## Decision

1. **The query document gains one additive key, `radius`** (version 1 stays):
   `{ "field": "MailingAddress", "miles": 25, "latitude": 42.3126, "longitude": -71.0553 }`.
   The server checks it like every other part: the field must be a compound address or a
   location field of the query's object that the user can read (describe), miles a whole number
   from 1 to 500, latitude and longitude numbers in range. Latitude, longitude and miles are
   bind variables in `DISTANCE(field, GEOLOCATION(:lat, :lon), 'mi') < :miles`. No text a
   person typed becomes query text.
2. **The point is looked up by the server, never geocoded.** A person types a US postal code
   (read from the shipped table) or the Id of a record whose address is used (read from that
   record's own stored geocode, as the user). A record with no geocode falls back to the center
   of its postal code and says so; with neither it is refused with the reason. A typed street
   address is refused with a message saying to use the postal code or a record, so nothing is
   ever sent outside Salesforce.
3. **The table is a static resource, one line of `zip,latitude,longitude` records separated
   by semicolons** (`BarnZipCentroids`, about 784 KB, 33,791 rows). Custom metadata cannot
   hold that many rows (the platform and package limits, and one row per code would add
   thousands of metadata records to every install); a static resource is one file, counts
   nothing against labels, and is read once per transaction. One line, so a source diff
   counts it as one line and a lookup is a single `indexOf` on the text. It is read in system
   mode, as `BarnHelp` reads its catalogs: packaged text every user may use.
4. **Data source and license.** US Census Bureau, 2023 Gazetteer Files, ZIP Code Tabulation
   Areas national file (`2023_Gaz_zcta_national.txt`, from
   https://www2.census.gov/geo/docs/maps-data/data/gazetteer/2023_Gazetteer/2023_Gaz_zcta_national.zip).
   The point per code is the file's internal point (`INTPTLAT`, `INTPTLONG`), rounded to four
   decimals (about 10 meters). It is a work of the US federal government and so in the public
   domain (17 U.S.C. 105): no license, attribution or fee applies, though the source is named
   in the admin guide. A ZCTA is the Census Bureau's area approximation of a ZIP Code, so a
   post office box only code, or a code created after the 2020 census, may have no row; such a
   code is refused with a message. Refreshing the table is a new static resource from a newer
   Gazetteer, with no code change.
5. **A record with no geocode is never within a distance, and Find says so.** `DISTANCE`
   returns null for it, so it never matches. After a run, Find counts (up to 10,000) the records
   the query's other conditions keep that have a postal code but no geocode on a standard
   address, and shows how many with the reason, so a missing person is never silent. A
   location custom field has no postal code to count, so it gives no such count.
6. **Everything that reads a query document gets the radius for free,** because `QueryCompiler`
   compiles it: results, export, server export, Bulk Update, Bulk Delete, summaries, donor
   segments and indicator sources. Super Transformer, which rebuilds a document from what Find
   hands over, is given the radius with the filter and related records, so a bulk change counts
   the same records Find found. The typed query text reads `DISTANCE(...)` back into the
   `radius` key (miles and `<` only), so switching between the builder and text loses nothing.

## Alternatives considered

- **Geocode typed addresses with a service.** Rejected by the plan: an outside callout and a
  dependency on a vendor; also no required Setup step.
- **Custom metadata rows, one per code.** Rejected: 33,791 records per install and no way to
  query them cheaply; the one file is smaller and faster.
- **Compute distance in Apex from each record's postal code against the table.** Rejected: it
  would read every record and miss the geocodes Salesforce already stores, and cannot be a
  query condition, so it would break counts, exports and bulk changes that compile the document.
- **A zipped resource.** Rejected: Apex cannot read an archive's entries cheaply, and a binary
  file hides the data from review.

## Consequences

- Radius works only where Salesforce has stored geocodes (standard addresses with geocoding
  turned on, or a location field). The admin guide says so and where the setting is.
- US postal codes only; other countries are a later table.
- The table adds about 784 KB to the Core package; no Apex size or label budget is affected beyond
  five short labels.
- The ZCTA table is a snapshot: a newer Gazetteer replaces the resource.
