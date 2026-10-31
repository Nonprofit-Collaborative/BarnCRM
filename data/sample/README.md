# Sample data

## Purpose

Tracked as **C-10** in the product plan: 200 realistic households (440 contacts), 25
organizations, 60 connections between people in different households and 80 affiliations,
plus, where the Giving package is installed, three years of gifts against 8 funds and 7
appeals, 24 pledges and recurring commitments with their installments, 11 asks across the
pipeline's stages and outcomes (two won as pledges), 30 soft credits and
24 tributes. A contributor or reviewer sees the product working immediately, with numbers
in the reports, without hand-entering data.

## Format

The sample set is not a `sf data import tree` plan. It ships as two JSON static resources,
loaded and removed inside the org by Apex, so that every record goes through the same
triggers a real import would (automatic household naming, greetings, member counts,
default allocations, installment schedules, automatic household soft credits), and so that
"remove sample data" is a single in-app action rather than a manual delete:

- `packages/core/main/default/staticresources/SampleData.json`, read by `SampleDataLoader`:
  households, people, organizations, connections, affiliations.
- `packages/giving/main/default/staticresources/GivingSampleData.json`, read by
  `GivingSampleData` in the Giving package: funds, appeals, gifts with their allocations,
  commitments, soft credits, tributes. It ships with Giving, so an org without Giving never
  carries it.

Both files are generated, not hand-edited, by
`scripts/data/generate-sample-data.py` (Python 3, standard library only, no dependencies to
install). The generator is deterministic: fixed random seeds mean running it again
produces byte-identical files, so a regenerated file is easy to diff in code review.

The JSON shape:

```json
{
  "households": [
    {
      "key": "H001",
      "name": null,
      "customName": false,
      "anniversary": "1998-06-12",
      "address": { "street": "...", "city": "...", "state": "...", "postalCode": "..." },
      "members": [
        {
          "firstName": "...",
          "lastName": "...",
          "salutation": "Mr.",
          "householdRole": "Head",
          "email": "...@example.org",
          "phone": "...",
          "mailingStreet": "...",
          "mailingCity": "...",
          "mailingState": "...",
          "mailingPostalCode": "...",
          "birthdate": "1975-03-02",
          "preferredName": "...",
          "deceased": false
        }
      ]
    }
  ],
  "organizations": [{ "key": "O001", "name": "...", "type": "business", "website": "...", "phone": "..." }],
  "relationships": [
    {
      "person": "H001-1",
      "relatedPerson": "H070-2",
      "type": "Sibling",
      "status": "Current",
      "startDate": "2004-05-12",
      "endDate": null,
      "description": "..."
    }
  ],
  "affiliations": [
    {
      "person": "H001-1",
      "organization": "O005",
      "role": "Board Member",
      "status": "Current",
      "isPrimary": true,
      "startDate": "2016-02-08",
      "endDate": null
    }
  ]
}
```

Every member carries a `key` of the form `H001-1`, and every household and organization
carries its own (`H001`, `O005`). The loader writes these to `Sample_Data_Key__c` on the
Account and the Contact, which is the whole join between the two files: the Giving payload
names its donors by the same keys, so a gift finds its donor in a later transaction without
depending on names or on the order records were inserted in.

The Giving payload:

```json
{
  "funds": [{ "key": "General Fund", "name": "General Fund", "accountingCode": "4000", "restricted": false, "active": true, "description": "..." }],
  "appeals": [{ "key": "Spring Appeal", "name": "Spring Appeal", "parent": "Annual Fund", "goal": 40000, "cost": 3200, "startDaysAgo": 210, "endDaysAgo": 120, "active": false, "description": "..." }],
  "commitments": [
    {
      "key": "C001",
      "donor": "H067-1",
      "type": "Recurring",
      "frequency": "Monthly",
      "amount": 160,
      "expectedTotal": null,
      "installmentsPlanned": null,
      "startDaysAgo": 201,
      "endDaysAgo": null,
      "dayOfMonth": 5,
      "status": "Active",
      "fund": "General Fund",
      "appeal": null
    }
  ],
  "gifts": [
    {
      "key": "G0001",
      "donor": "H001-1",
      "daysAgo": 957,
      "amount": 250,
      "type": "Card",
      "status": "Received",
      "appeal": null,
      "acknowledgmentStatus": "Acknowledged",
      "paymentReference": "TXN-400001",
      "commitment": null,
      "allocations": [{ "fund": "Memorial Fund", "amount": 250 }]
    }
  ],
  "tributes": [{ "gift": "G0011", "type": "In memory of", "honoreePerson": "H008-2", "recipientPerson": "H008-1", "message": "..." }],
  "softCredits": [{ "gift": "G0011", "person": "H042-1", "role": "Solicitor", "amount": 2500 }],
  "asks": [{ "key": "A001", "donor": "H004-1", "stage": "Identified", "outcome": "Open", "amount": 1000, "targetDaysAgo": -90, "stageDaysAgo": 12, "closedDaysAgo": null, "nextAskDaysAgo": null, "nextStep": "...", "fund": null, "appeal": null, "commitment": null }]
}
```

Asks use the packaged default stages. A negative offset is a date still to come (a target
date, a next ask date). A won ask names the sample pledge that closed it in `commitment`, so
asks load in the reference data stage with the commitments. A stage the org has removed from
its stage list loads blank and the ask takes the org's first stage.

Giving dates are day offsets (`daysAgo`, `startDaysAgo`, `endDaysAgo`), not calendar dates.
The loader counts them back from the day the set is loaded, so a set loaded a year from now
still has gifts in the current year and the retention reports, the fiscal-year rollups and
the dashboard all have something true to show. A gift that reverses another names it by key
in `originalGift` and carries the `refundReason`; nothing in the file carries a receipt
number, because a receipted gift cannot be deleted (ADR-0024) and the set has to stay
removable.

`name` is `null` for every household except the roughly three with `customName: true`
(and the staff household), because household name, formal greeting, and informal greeting
are computed by the household naming trigger, not by the sample data set, exactly as a
real import would produce them (canonical model Section 5, rule R-H4). Custom-name
households carry the name directly, matching `Custom_Name__c` behavior (rule R-H8).

The set deliberately includes: households sharing a surname and households with differing
surnames, a few hyphenated surnames, single-person households, about ten
three-generation households, five households with a deceased member, three households
with a custom name (for example "The Reverend and Mrs. Alvarez"), one household guaranteed
to be "The Garcia Family" (used by the admin guide's walkthrough), and one "Staff
Household" containing Maria, David, Priya, Tom, Jen, and Sam so the personas are always
findable in a freshly loaded org. Mailing addresses spread across a dozen US states.

The giving history is shaped the way a real list is, so the reports have something to
report on: multi-year donors who give in all three years, lapsed donors whose last gift is
more than eighteen months old, donors whose first gift is in the last few months, a handful
of major donors, and about a fifth of households who have never given. Gift sizes are
weighted small (most gifts under 500, a few above 10,000). The set also holds two refunded
gifts and one written-off gift, each recorded as R-G3 records them (the original keeps its
amount and takes the reversed status, and a linked negative gift carries the money back
out), so the ADR-0022 rollup behaviour is visible rather than theoretical, and one lapsed
monthly donor whose last three installments are overdue.

## Regeneration

Change the generator, then run:

```bash
python3 scripts/data/generate-sample-data.py
```

This overwrites both static resource bodies in place. Commit the regenerated files
alongside the generator change. The script prints the counts of every kind of record and
the resulting file sizes (each kept under 400 KB) so a change that grows the set
unexpectedly is caught at generation time, not in review.

## Loading and removing

`SampleDataLoader.load()` (Apex) reads the Core static resource and starts
`SampleDataStageBatch`, which runs one stage per execute: households and organizations
first (record types by DeveloperName, `Sample_Data__c` true, `Sample_Data_Key__c` set),
then contacts in chunks of 100, then the connections and affiliations. Its finish starts
any module sample set. Giving is one: `GivingSampleData` implements the Core
`SampleDataModule` interface, Core finds it by name at runtime (ADR-0017), and its own
stages (`GivingSampleData.LoadStages`, run by the same batch class) insert the funds, appeals
and commitments and then the gifts in chunks of 100. Batch Apex rather than a queueable
chain, because Developer Edition, trial and scratch orgs stop a chain after five jobs.

`SampleDataLoader.remove()` starts deleting every record carrying the flag, in stages of
about a hundred records run by `SampleDataRemoveBatch` (a `SampleDataStageBatch` subclass, so
removal has no queueable chain limit either): each module's records first
(`GivingSampleData.RemoveStages`), because a gift points at a person and a household, then
Core's (`SampleDataRemoveStages`): connections, affiliations, contacts and accounts. Allocations, soft credits and tributes are details of a gift, and
installments are details of a commitment, so they go with their master. Both actions are
exposed to admins through **Nonprofit Settings > Sample Data** (`sampleDataManager` LWC);
see `docs/admin-guide/sample-data.md`.
`scripts/org/seed-sample-data.sh` runs the load from the command line for contributors
setting up a scratch org.
