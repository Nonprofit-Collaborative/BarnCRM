# Migrating from Nonprofit Cloud

**Package:** Core and Giving | **Iteration:** v0.5

## 1. What it does

If your donors and gifts are in Salesforce Nonprofit Cloud, Open Impact
ships four ready-made import mappings that read Nonprofit Cloud's own exports: your people, and
your gifts with the funds they were designated to. You export each file with Data Loader or
Workbench, without renaming a column, and load it through the **Import** tab like any other
file, with a dry run first and an undo afterwards.

The mappings only name columns. Nothing in Open Impact depends on Nonprofit Cloud being
installed, so they work the same whether you are moving to a new org or loading into the org
Nonprofit Cloud is in.

## 2. How to turn it on

Open Impact brings the person accounts mapping, and the Giving module brings the three gift
mappings. In an org that has never opened the **Import** tab they appear the first time it
opens. In an org that already had the generic mappings, add them once from Health Check:

1. Open the **Open Impact** app, click **Open Impact Settings** and choose **Health**.
2. The report opens (click **Re-run** if it is from earlier). A finding reads "4 shipped
   import templates are missing" (a higher number if other shipped mappings are missing too)
   and names them.
3. Select **Restore import templates**. Your own mappings, and any shipped mapping you have
   edited, are not touched.
4. Open the **Import** tab. The list now has **Nonprofit Cloud: person accounts**,
   **Nonprofit Cloud: gift transactions**, **Nonprofit Cloud: undesignated gifts**
   and **Nonprofit Cloud: organization gifts**.

Before loading gifts, create in Open Impact every fund and appeal the gifts name, with the same
names they have in Nonprofit Cloud (see [Funds](funds.md) and [Appeals](appeals.md)), and mark
one fund as the default. A gift naming a fund or appeal Open Impact does not have is rejected
in the dry run, naming it.

## 3. A five-minute walkthrough (as Maria)

The four sample files in [samples](samples/) are small exports in exactly the shape the steps
in section 4 produce. Create a default fund called **General Fund**, a fund called
**Scholarships** and an appeal called **Spring Appeal** first.

1. Open the **Import** tab, select **Nonprofit Cloud: person accounts**, then **Next**, and
   upload `npc-person-accounts.csv`. Every column is already mapped, `PersonEmail` to
   the person's email, `PersonMailingCity` to their mailing city, and so on.
2. Dry run, then commit. Ana Okafor and Wei Lee are created, each with a household of their
   own.
3. Import `npc-gift-transactions.csv` with **Nonprofit Cloud: gift transactions**.
   Leave donation matching at **Match or create**. The dry run says 2 rows would create a gift
   and 2 would be rejected. The rejected two are the two lines of one gift split across two
   funds, each saying "The split adds up to 300.00, not the gift amount of 500.00." (and 200.00
   for the other). Section 5 explains why, and how to load it.
4. Commit. Open Ana Okafor: she has two gifts, one of 250.00 to Scholarships with the appeal
   Spring Appeal and the payment method Card, one of 100.00 to General Fund. She was found by
   her email, not created again.
5. Import `npc-undesignated-gifts.csv` with **Nonprofit Cloud: undesignated
   gifts**. Both gifts are created, to General Fund, one for Ana and one for Wei.
6. Import `npc-organization-gifts.csv` with **Nonprofit Cloud: organization
   gifts**. Riverside Foundation is created as an organization and gives one gift of 1,000.00,
   split 600.00 to Scholarships and 400.00 to General Fund. This file is the split gift of
   step 3 done the right way: two lines combined into one row.
7. Load any of the gift files again and dry run it. Every gift row says it matches a gift you
   already have: the gift transaction's record ID is each gift's external ID, so nothing is
   created twice.

## 4. Moving everything, step by step

Do it in this order. People come before gifts because the people file carries each person's
full details (address, phones, preferences), which a gift file does not. A donor the gift file
names on several rows is created once either way, but only with the few details a gift row
has. With the people already loaded, every gift row finds its donor by email. An export of up
to 500,000 rows can be dry run as one file; split anything larger.

1. **Funds and appeals.** Create them in Open Impact by hand, with the names they have in
   Nonprofit Cloud (gift designations and campaigns). There is no import for them yet.
2. **Check the gift statuses.** In Workbench or the Developer Console, run
   `SELECT Status, COUNT(Id) FROM GiftTransaction GROUP BY Status`. The queries below take the
   status `Paid`, money received. If your org uses another value for a completed gift, use it
   instead in every query.
3. **People.** Export them with this query and load the file with **Nonprofit Cloud:
   person accounts**.

   ```sql
   SELECT Salutation, FirstName, LastName, PersonEmail, Phone, PersonMobilePhone,
       PersonHomePhone, PersonBirthdate, PersonMailingStreet, PersonMailingCity,
       PersonMailingState, PersonMailingPostalCode, PersonMailingCountry,
       PersonHasOptedOutOfEmail, PersonDoNotCall
   FROM Account
   WHERE IsPersonAccount = true
   ```

4. **Gifts from people, with their designations.** Export one row per designation, and load
   the file with **Nonprofit Cloud: gift transactions**.

   ```sql
   SELECT GiftTransactionId, GiftTransaction.OriginalAmount, GiftTransaction.TransactionDate,
       GiftTransaction.PaymentMethod, GiftTransaction.PaymentIdentifier,
       GiftTransaction.Campaign.Name, GiftTransaction.Donor.FirstName,
       GiftTransaction.Donor.LastName, GiftTransaction.Donor.PersonEmail,
       GiftTransaction.Donor.PersonMailingPostalCode, GiftDesignation.Name, Amount
   FROM GiftTransactionDesignation
   WHERE GiftTransaction.Status = 'Paid' AND GiftTransaction.Donor.IsPersonAccount = true
   ORDER BY GiftTransactionId
   ```

5. **Gifts from organizations.** The same query with the donor's name in place of the four
   person columns, loaded with **Nonprofit Cloud: organization gifts**.

   ```sql
   SELECT GiftTransactionId, GiftTransaction.OriginalAmount, GiftTransaction.TransactionDate,
       GiftTransaction.PaymentMethod, GiftTransaction.PaymentIdentifier,
       GiftTransaction.Campaign.Name, GiftTransaction.Donor.Name, GiftDesignation.Name, Amount
   FROM GiftTransactionDesignation
   WHERE GiftTransaction.Status = 'Paid' AND GiftTransaction.Donor.IsPersonAccount = false
   ORDER BY GiftTransactionId
   ```

6. **Gifts with no designation.** A gift nobody designated has no designation row, so steps 4
   and 5 miss it. Export it from the gift itself and load it with **Nonprofit Cloud:
   undesignated gifts**. It goes to your default fund.

   ```sql
   SELECT Id, OriginalAmount, TransactionDate, PaymentMethod, PaymentIdentifier,
       Campaign.Name, Donor.FirstName, Donor.LastName, Donor.PersonEmail,
       Donor.PersonMailingPostalCode
   FROM GiftTransaction
   WHERE Status = 'Paid' AND Donor.IsPersonAccount = true
       AND Id NOT IN (SELECT GiftTransactionId FROM GiftTransactionDesignation)
   ```

   Undesignated gifts from organizations: run the same query with `Donor.IsPersonAccount =
   false` and `Donor.Name` in place of the four donor columns. Then give the file the
   organization gifts shape: put `GiftTransaction.` in front of every heading, rename the
   first to `GiftTransactionId`, and add the columns `GiftDesignation.Name` (your default
   fund's name on every row) and `Amount` (the gift amount again). Load it with **Nonprofit
   Cloud: organization gifts**.

7. **Split gifts.** Sort the files from steps 4 and 5 by the first column. Where a gift has
   more than one line, keep the first, add the columns `Fund 2` and `Amount 2` (up to `Fund 5`
   and `Amount 5`), copy the other lines' designation and amount into them, and delete those
   lines. Section 5 says why.
8. **Translate what does not match.** Payment methods: Open Impact reads Cash, Check, Card,
   ACH, Stock and In-kind, plus common words such as "Credit Card", "EFT" and "Wire Transfer".
   Any other value is rejected in the dry run, naming it and the values to use; use **Find and
   Replace** in the spreadsheet on that column.
9. **Recreate what the mappings do not load** (section 6).

In Data Loader, choose **Export**, pick the object named after `FROM`, and paste the query into
the query box. In Workbench, choose **Queries**, **SOQL Query**, paste it, and choose **Bulk
CSV**. Before the full export, add `LIMIT 5` to a query and compare the rows with the records
they came from: the field names above come from Salesforce's documentation, and an org can
differ.

## 5. Why four mappings and not one

A mapping remembers the columns of the last file loaded with it, so one mapping serves one
file shape. The shapes differ in ways that matter:

- **People and gifts are separate files** because a gift file cannot carry a person's full
  details without repeating them on every gift.
- **Gifts from organizations have their own file** because a column that makes the donor an
  organization would make every person in the same file an organization too.
- **Undesignated gifts have their own file** because they are missing from the designation
  export, which is the only export that says where a designated gift's money went.
- **A split gift arrives as one line per designation.** Open Impact reads a split from one row
  (Fund 1 with Amount 1, Fund 2 with Amount 2, and so on). Each line on its own claims part of
  the gift is the whole gift, so the mapping loads a line's designation amount as **Amount 1**:
  the parts then do not add up to the gift, and the line is rejected where you can see it,
  rather than loaded as a gift to one fund only.

## 6. What does not come across yet

These are not loaded by the four mappings. Each has what to do in the meantime.

| Not loaded | What to do meanwhile |
|---|---|
| Households and who is in them | Each person gets a household of their own. Merge the households of people who live together ([Household merge and split](household-merge-split.md)), or load couples in one row with the second person's columns mapped to **Contact 2** ([Importing](importing.md), section 4). |
| Relationships and affiliations | No import yet (planned for v0.7). Enter the ones you need by hand ([Relationships](relationships.md), [Affiliations](affiliations.md)). |
| Gift commitments (pledges and recurring gifts) and their schedules | No import yet. Create each active commitment by hand ([Commitments](commitments.md)) before loading gifts. With **Match or create**, a gift dated near one of its scheduled payments pays it; older gifts load as gifts on their own. |
| Soft credits | A soft credit loads only on the same row as a new gift, and Nonprofit Cloud exports them separately. Credits between household members are made automatically; add others by hand ([Soft credits](soft-credits.md)). |
| Tributes | Same: add them by hand to the gift ([Tributes](tributes.md)). |
| Refunds and write-offs | The exports take paid gifts only. Record refunds in Open Impact after the gift is loaded ([Refunds](refunds.md)). |
| Additional addresses | Only the mailing address loads. Add seasonal and other addresses by hand ([Addresses](addresses.md)). |
| Funds and appeals | Create them by hand first (section 4, step 1). |
| An organization's details | A gift file creates an organization with its name only. Add its address and phone by hand. |
| In-kind gifts (payment method In-kind) | Open Impact wants an in-kind gift's value as its fair market value, with no amount, so these rows are rejected. Load them with the **Generic gift list**, the value mapped to **Gift: fair market value**. |

## 7. Loading into the org Nonprofit Cloud is in

If Open Impact is installed in the same org, your people are already there as person accounts.
Skip step 3 of section 4: the gift files find each donor by email. Two things differ in an org
that keeps people as person accounts:

- A person a gift file has to create gets their name only. Their email and postal code are
  skipped, and the run log says "The mapping refers to Email, which this org does not have.
  Those values were skipped." Make sure every donor exists before loading gifts. The person
  accounts mapping is for loading into a new org, where people are stored as contacts.
- An organization donor is found by name only if its account is an Open Impact organization.
  A business account of another record type gets a new Open Impact organization of the same
  name. Check the dry run's "would create" count for organizations before you commit.

## 8. Common mistakes

**Every line of a split gift is rejected with "The split adds up to ..., not the gift amount of
...".** The gift has more than one designation. Combine its lines into one row (section 4, step
7) and load the file again: the rows already loaded are matched, not duplicated.

**The same person appears on several records after a gift file.** The donor had no email
address, so **Email exact** had nothing to match or group their rows on, and each row created
them. Give such donors an email address before the export, or choose **Name plus postal
code**, which the gift files also carry (read its warning on the matching step first). Either
way, check the dry run's "would create" count: a donor who can be matched is created once
however many gifts they have, and a couple at one address are told apart by first name.

**A person's first name changed after a gift file.** Where only one person has the row's email,
a row with a different first name is matched to them and their first name is updated (see
[Importing](importing.md)). Check the dry run's Updated rows before you commit, and correct the
file where a gift names the donor differently, for example "Bob" for "Robert".

**Salesforce warned about duplicates and the import saved the people anyway.** A duplicate
rule set to alert does not stop an import, as it would not stop a bulk load. Run the duplicate
scan afterwards ([Duplicates](duplicates.md)). A rule set to **Block** still rejects the row
with the rule's message.

**Rows rejected with "No appeal is named ..." or "No fund is named ...".** The campaign or
designation name is not an appeal or fund in Open Impact. Create it with exactly that name, or
correct the name in the file.

**A column you set to Do not load is mapped again next time.** Open Impact's column library
recognises some export headings on its own, for example a donor's name, and suggests them even
after you have set them to **Do not load**. Check the column step on every load, or delete the
column from the file.

## Column reference

Each mapping reads the columns its query in section 4 exports. The headings match whatever
their capitals.

| Column heading | Loads into |
|---|---|
| `GiftTransactionId` (or `Id` for undesignated gifts) | Gift: external ID |
| `OriginalAmount` | Gift: amount |
| `TransactionDate` | Gift: date |
| `PaymentMethod` | Gift: payment method |
| `PaymentIdentifier` | Gift: payment reference |
| `Campaign.Name` | Gift: appeal |
| `Donor.FirstName`, `Donor.LastName`, `Donor.PersonEmail`, `Donor.PersonMailingPostalCode` | The donor's first name, last name, email and postal code |
| `Donor.Name` (organization gifts) | The organization's name |
| `GiftDesignation.Name`, `Amount` | Fund 1, Amount 1 |
| `Fund 2` to `Fund 5`, `Amount 2` to `Amount 5` | Added by you for a split gift |
| `Salutation`, `FirstName`, `LastName`, `Phone` | The person's field of the same name |
| `PersonEmail`, `PersonMobilePhone`, `PersonHomePhone`, `PersonBirthdate` | Email, mobile, home phone, birthdate |
| `PersonMailingStreet`, `City`, `State`, `PostalCode`, `Country` | The mailing address |
| `PersonHasOptedOutOfEmail`, `PersonDoNotCall` | Email opt out, do not call |

The gift columns are prefixed `GiftTransaction.` in the designation exports.
