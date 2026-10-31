# AI-Readiness Export

**Package:** Core
**Feature:** AIR-01 (plan Section 6.1 item 7, release 0.13, decision D-154, ADR-0152)

## What It Does

The **AI-Readiness Export** section of **Org Optimizer** downloads one zip file (the pack) that
helps an AI tool of your choice understand your data: what each kind of record and field means,
how records connect, how complete each field is, and, if you want, the records themselves with
sensitive fields left out or masked.

**BarnCRM never calls an AI service.** It builds the pack in your browser and downloads it. You
choose the AI tool, read its terms, and upload what you decide to share. Nothing is sent
anywhere by BarnCRM, and nothing in the pack is saved in Salesforce.

The pack holds:

| File | What it holds |
|---|---|
| `README.md` | A plain-language summary: the files, the kinds of record, how records connect, which fields were left out or masked, data quality notes, and how to use the pack with an AI tool |
| `schema.json` | The canonical-model JSON: every kind of record and field you chose, with type, length, required, picklist values, help text, formula, lookups, fill rate and privacy handling, plus the relationships and data quality checks (format below) |
| `data-dictionary.csv` | The same fields as a spreadsheet, with the columns of the [Data Dictionary](data-dictionary.md) download |
| `data/<Object>.csv` | Only with **Include Records**: one file of records per kind of record, headed by field API names |

It reuses what BarnCRM already has: the Data Dictionary's reading of fields, Field
Utilization's fill rates, the Data Quality checks, and Find's export (the same permission, the
same row limit, the same field security).

## How to Turn It On

You need the BarnCRM Admin role (the BarnCRM Admin permission set, which carries the Manage
BarnCRM Settings and Find and Export Records permissions). It shows you the **AI-Readiness
Export** section of the **Org Optimizer** tab. Nobody else sees it. There is nothing to schedule
and no setting to change.

**Include Records** and **Include Data Quality Checks** need Find and Export Records. Without it
they are turned off and the page says why; the schema and dictionary still download.

## A Five-Minute Walkthrough

Start from the sample data (see [Sample data](sample-data.md)).

1. Open the **Org Optimizer** tab and choose **AI-Readiness Export**.
2. **Kinds of Record** starts with Core's data objects plus Account and Contact chosen, as in the
   Data Dictionary. For this walkthrough, move everything out of **Selected** except **Contact**.
3. Leave **Include Records** ticked, and tick **Include Fill Rates**.
4. Press **Review Sensitive Fields**. The page reads Contact's fields and lists the ones that may
   identify a person or hold private details, such as **Email** (an email address), **Mobile
   Phone** (a phone number), **Birthdate** and **Mailing Street**. Each starts at **Leave Out**.
5. Set **Last Name** to **Mask** and **Email** to **Keep**.
6. Press **Download Pack**. The page counts fill rates, reads the records a page at a time, then
   downloads `AI_Readiness_Export-` and today's date ending `.zip`, and says how many kinds of
   record and records it holds.
7. Open the zip. In `data/Contact.csv`, **LastName** holds codes such as `masked-3f9a01c2b7`
   (the same last name always has the same code in this pack), **Email** holds the addresses,
   and **Birthdate** and **MobilePhone** are not there. `README.md` lists those choices under
   **Privacy**.

## Sensitive Fields

A field is flagged when it looks like it may identify a person or hold private details. The
flag is worked out from the field's type and API name, so it also catches custom fields:

| Why it is flagged | Fields |
|---|---|
| Email address | Every email field |
| Phone number | Every phone field |
| Encrypted | Every encrypted text field |
| Name | A person's first, middle and last name and suffix, and the Name of Contact and Lead |
| Birth date | Names containing birth or dob |
| Address | Street, postal code, latitude and longitude parts |
| Identity or financial number | Names containing ssn, social security, tax id, passport, driver, bank, routing, iban or account number |
| Private detail | Names containing gender, ethnic, race, religion, medical, health, diagnosis, disability, income or salary |
| Long free text | Long and rich text fields (notes and descriptions often hold personal details) |

For each flagged field you choose:

- **Leave Out** (the start): the field is not in the record file. `schema.json` still lists it,
  with `"handling": "leaveOut"`, so the AI tool knows it exists.
- **Mask**: each value becomes `masked-` and ten letters and digits. The same value gets the same
  code everywhere in this pack, so counting and grouping still work, but the code cannot be
  turned back into the value. Each pack uses a new secret key, so codes differ between packs.
- **Keep**: the values are exported as they are.

The flag is a starting point, not a guarantee. Read the list of fields before you download, and
leave out anything your AI tool does not need.

## Records

**Include Records** reads each kind of record through Find's export: you need Find and Export
Records, you get only the records and fields you can read, and each kind of record stops at the
**Find export row limit** in BarnCRM Settings (50,000 unless changed). When a kind of record has
more, the page names it and `schema.json` marks it with `"recordsStoppedAtLimit": true`.

- The first column is **Id**, and lookup fields hold record Ids, so the AI tool can join files
  (`Contact.AccountId` matches `Account.Id`).
- Address, location and file-body fields are not exported (their parts, such as MailingCity,
  are).
- Dates and date-times are written as Salesforce returns them: dates as `YYYY-MM-DD`, date-times
  in UTC.
- Text that starts with `=`, `+`, `-` or `@` gets a leading apostrophe, as in every BarnCRM CSV.

## Data Quality Notes

- **Include Fill Rates** counts fill rates the way the Data Dictionary does, with Field
  Utilization's limits (an object over 1,000,000 records is not counted, and the page names it).
  `README.md` lists fields filled on fewer than 10% of records.
- **Include Data Quality Checks** adds each check of the Data Quality section with its count,
  such as people without an email address. If the checks cannot be read, the page says so and
  the pack leaves them out.

## The schema.json Format

```json
{
  "format": "barncrm-ai-readiness-export",
  "formatVersion": 1,
  "createdAt": "2026-10-31T15:04:05.000Z",
  "objects": [
    {
      "apiName": "Contact",
      "label": "Contact",
      "custom": false,
      "recordFile": "data/Contact.csv",
      "recordCount": 120,
      "recordsStoppedAtLimit": false,
      "fields": [
        {
          "apiName": "Email",
          "label": "Email",
          "type": "email",
          "length": 80,
          "precision": null,
          "required": false,
          "unique": false,
          "externalId": false,
          "custom": false,
          "picklistValues": [],
          "helpText": null,
          "formula": null,
          "relatedTo": [],
          "fillRate": 0.85,
          "sensitive": "email",
          "handling": "keep",
          "inRecordFile": true
        }
      ]
    }
  ],
  "relationships": [{ "object": "Contact", "field": "AccountId", "relatedTo": ["Account"] }],
  "dataQuality": {
    "lowFillThreshold": 0.1,
    "checks": [{ "key": "people-no-email", "title": "People Without an Email", "count": 12 }]
  }
}
```

- `recordFile`, `recordCount` and `recordsStoppedAtLimit` are null when records were not
  included.
- `fillRate` is a share from 0 to 1, or null when not counted.
- `sensitive` is null or one of `email`, `phone`, `encrypted`, `name`, `birthDate`, `address`,
  `identityNumber`, `privateDetail`, `freeText`; `handling` is null for a field not flagged, or
  `leaveOut`, `mask` or `keep`.
- `formatVersion` changes only when a key is removed or changes meaning; new keys may be added.

## Common Mistakes

**Uploading more than the question needs.** Many AI tools keep what you upload, or train on it,
unless you turn that off. Start with `schema.json` alone; it holds no records.

**Treating the flags as a privacy review.** The flags catch common field names and types. A
custom field named `Notes_2__c` of short text is not flagged. Read the field list.

**Expecting every record.** Each kind of record stops at the Find export row limit, and you get
only what you can read.

## Related

- [Org Optimizer](org-optimizer.md)
- [Data Dictionary](data-dictionary.md)
- [Field utilization](field-utilization.md)
- [Find and export](find.md)
