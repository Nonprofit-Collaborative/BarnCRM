# Migrating from NPSP

**Package:** Core and Giving | **Iteration:** v0.5

## 1. What it does

If your donors and gifts are in the Nonprofit Success Pack (NPSP), Open Impact ships three
ready-made import mappings that read NPSP's own exports: your contacts, and the payments your
donors made, from people and from organizations. You export each file with Data Loader or
Workbench, without renaming a column, and load it through the **Import** tab like any other
file, with a dry run first and an undo afterwards.

The mappings only name columns. Nothing in Open Impact depends on NPSP being installed.

## 2. How to turn it on

Open Impact brings the contacts mapping, and the Giving module brings the two payment mappings.
In an org that has never opened the **Import** tab they appear the first time it opens. In an
org that already had the generic mappings, add them once from Health Check:

1. Open the **Open Impact** app, click **Open Impact Settings** and choose **Health**.
2. The report opens (click **Re-run** if it is from earlier). A finding reads "3 shipped
   import templates are missing" (a higher number if other shipped mappings are missing too)
   and names them.
3. Select **Restore import templates**. Your own mappings, and any shipped mapping you have
   edited, are not touched.
4. Open the **Import** tab. The list now has **NPSP: contacts**, **NPSP: opportunities and
   payments** and **NPSP: organization payments**.

Before loading gifts, create in Open Impact every appeal the gifts name, with the same names
as your NPSP campaigns (see [Appeals](appeals.md)), and a default fund (see [Funds](funds.md)).
A gift naming an appeal Open Impact does not have is rejected in the dry run, naming it.

## 3. A five-minute walkthrough (as Maria)

The three sample files in [samples](samples/) are small exports in exactly the shape the steps
in section 4 produce. Create a default fund called **General Fund** and an appeal called
**Year End 2024** first.

1. Open the **Import** tab, select **NPSP: contacts**, then **Next**, and upload
   `npsp-contacts.csv`. Every column is already mapped: the home email to the personal email,
   the work email to the work email, the preferred email to the preferred email, and so on.
2. Dry run, then commit. Ana Okafor and Robert Hale are created, each with a household of their
   own. Robert is marked deceased and do not call.
3. Import `npsp-payments.csv` with **NPSP: opportunities and payments**. Leave donation matching
   at **Match or create**. The dry run says 2 rows would create a gift and 1 would be rejected:
   "The tribute type Honor is not one Open Impact knows. Use one of: In honor of, In memory
   of."
4. Commit. Open Ana Okafor: she has a gift of 150.00 by Card with the appeal Year End 2024, and
   a gift of 50.00 by Check, reference 3312, in memory of Grace Okafor. She was found by her
   email, not created again.
5. In the file, replace `Honor` with `In honor of`, and load it again. The two gifts already
   loaded are matched, not duplicated, and the third is created with its tribute.
6. Import `npsp-organization-payments.csv` with **NPSP: organization payments**. Hillside Rotary
   Club is created as an organization and gives one gift of 500.00.

## 4. Moving everything, step by step

Do it in this order. People come before gifts because the contacts file carries each person's
full details (address, phones, preferences), which a gift file does not. A donor the gift file
names on several rows is created once either way, but only with the few details a gift row
has. With the people already loaded, every gift row finds its donor by email. An export of up
to 500,000 rows can be dry run as one file; split anything larger.

1. **Appeals and funds.** Create them in Open Impact by hand, with the names your NPSP
   campaigns and general accounting units have. There is no import for them yet.
2. **Contacts.** Export them with this query and load the file with **NPSP: contacts**.

   ```sql
   SELECT Salutation, FirstName, LastName, Title, Birthdate, Email, npe01__HomeEmail__c,
       npe01__WorkEmail__c, npe01__AlternateEmail__c, npe01__Preferred_Email__c, Phone,
       HomePhone, MobilePhone, MailingStreet, MailingCity, MailingState, MailingPostalCode,
       MailingCountry, npsp__Deceased__c, HasOptedOutOfEmail, DoNotCall
   FROM Contact
   ```

3. **Payments from people.** A payment is money received, with its method and check number, so
   each paid payment becomes one Open Impact gift. An opportunity paid in three payments
   becomes three gifts.

   ```sql
   SELECT Id, npe01__Payment_Amount__c, npe01__Payment_Date__c, npe01__Payment_Method__c,
       npe01__Check_Reference_Number__c, npe01__Opportunity__r.Campaign.Name,
       npe01__Opportunity__r.npsp__Primary_Contact__r.FirstName,
       npe01__Opportunity__r.npsp__Primary_Contact__r.LastName,
       npe01__Opportunity__r.npsp__Primary_Contact__r.Email,
       npe01__Opportunity__r.npsp__Primary_Contact__r.MailingPostalCode,
       npe01__Opportunity__r.npsp__Tribute_Type__c,
       npe01__Opportunity__r.npsp__Honoree_Name__c,
       npe01__Opportunity__r.npsp__Notification_Recipient_Name__c,
       npe01__Opportunity__r.npsp__Notification_Message__c
   FROM npe01__OppPayment__c
   WHERE npe01__Paid__c = true
       AND npe01__Opportunity__r.Account.npe01__SYSTEM_IsIndividual__c = true
   ORDER BY npe01__Opportunity__c, npe01__Payment_Date__c
   ```

   Load it with **NPSP: opportunities and payments**.
4. **Payments from organizations.** The same query with the organization's name in place of
   the four primary contact columns, loaded with **NPSP: organization payments**.

   ```sql
   SELECT Id, npe01__Payment_Amount__c, npe01__Payment_Date__c, npe01__Payment_Method__c,
       npe01__Check_Reference_Number__c, npe01__Opportunity__r.Campaign.Name,
       npe01__Opportunity__r.Account.Name,
       npe01__Opportunity__r.npsp__Tribute_Type__c,
       npe01__Opportunity__r.npsp__Honoree_Name__c,
       npe01__Opportunity__r.npsp__Notification_Recipient_Name__c,
       npe01__Opportunity__r.npsp__Notification_Message__c
   FROM npe01__OppPayment__c
   WHERE npe01__Paid__c = true
       AND npe01__Opportunity__r.Account.npe01__SYSTEM_IsIndividual__c = false
   ORDER BY npe01__Opportunity__c, npe01__Payment_Date__c
   ```

5. **Translate what does not match,** with **Find and Replace** on one column at a time:
   - Tribute type: `Honor` becomes `In honor of`, and `Memorial` becomes `In memory of`.
   - Payment method: Open Impact reads Cash, Check, Card, ACH, Stock and In-kind, plus common
     words such as "Credit Card" and "EFT". Any other value is rejected in the dry run, naming
     it and the values to use.
6. **One tribute per opportunity.** A tribute belongs to the opportunity, so every payment of
   it carries the tribute. Where an opportunity has several payments, clear the four tribute
   columns on all but its first payment (the file is sorted so they sit together).
7. **Funds, if you use them.** The payment export does not say which fund a gift went to, so
   every gift goes to your default fund (section 6 says how to add a fund column).
8. **Recreate what the mappings do not load** (section 6).

In Data Loader, choose **Export**, pick the object named after `FROM` (Payment for the payment
queries), and paste the query into the query box. In Workbench, choose **Queries**, **SOQL
Query**, paste it, and choose **Bulk CSV**. Before the full export, add `LIMIT 5` to a query
and compare the rows with the records they came from.

Check that every closed won gift has a payment:
`SELECT COUNT() FROM Opportunity WHERE IsWon = true AND npe01__Number_of_Payments__c = 0`. If
the count is not 0, those gifts were made while payments were switched off in NPSP and are not
in the payment export. Load them with the **Generic gift list**.

Check that every paid payment has an account: the two payment queries select on the
opportunity's account, so a payment whose opportunity has none is in neither file.
`SELECT COUNT() FROM npe01__OppPayment__c WHERE npe01__Paid__c = true AND npe01__Opportunity__r.AccountId = null`.
If the count is not 0, give those opportunities an account in NPSP before the export, or export
them with the people query, its last line changed to
`AND npe01__Opportunity__r.AccountId = null`, and load that file with **NPSP: opportunities
and payments** as well.

## 5. Why three mappings and not one

A mapping remembers the columns of the last file loaded with it, so one mapping serves one
file shape. The shapes differ in ways that matter:

- **Contacts and payments are separate files** because a gift file cannot carry a person's full
  details without repeating them on every gift.
- **Payments, not opportunities.** A payment says when the money came, how, and the check
  number. An opportunity paid in several payments is several gifts in Open Impact, and a
  pledge's unpaid payments are not gifts at all.
- **Payments from organizations have their own file** because a column that makes the donor an
  organization would make every person in the same file an organization too.

## 6. What does not come across yet

These are not loaded by the three mappings. Each has what to do in the meantime.

| Not loaded | What to do meanwhile |
|---|---|
| Households and who is in them | Each contact gets a household of their own. Merge the households of people who live together ([Household merge and split](household-merge-split.md)), or load couples in one row with the second person's columns mapped to **Contact 2** ([Importing](importing.md), section 4). Household names are made by Open Impact's naming. |
| Relationships and affiliations | No import yet (planned for v0.7). Enter the ones you need by hand ([Relationships](relationships.md), [Affiliations](affiliations.md)). |
| Recurring donations and their schedules | No import yet. Create each active recurring gift by hand as a commitment ([Commitments](commitments.md)) before loading payments. With **Match or create**, a payment dated near one of its scheduled payments pays it; older payments load as gifts on their own. |
| General accounting unit allocations | Every gift goes to the default fund. For opportunities with one allocation, export `SELECT npsp__Opportunity__c, npsp__General_Accounting_Unit__r.Name FROM npsp__Allocation__c`, add `npe01__Opportunity__c` to the payment query, and fill a new column headed `Fund` from the allocation file with a lookup on the opportunity. Delete the opportunity column before loading, and check on the column step that `Fund` reads **Gift: fund**. |
| Soft credits (contact roles, partial and account soft credits) | A soft credit loads only on the same row as a new gift, and NPSP exports them separately. Credits between household members are made automatically; add others by hand ([Soft credits](soft-credits.md)). |
| More than one tribute on a gift | Only the tribute on the opportunity loads. Add others by hand ([Tributes](tributes.md)). |
| Additional and seasonal addresses | Only the mailing address loads. Add others by hand ([Addresses](addresses.md)). |
| Written-off and unpaid payments | The exports take paid payments only. Refunds are recorded in Open Impact after the gift is loaded ([Refunds](refunds.md)). |
| An organization's details | A payment file creates an organization with its name only. Add its address and phone by hand. |
| In-kind gifts | Their payments have no payment method, so the rows are rejected with "The gift has no payment method. Map a column to it, or give the mapping a default payment method." Load them with the **Generic gift list**, the value mapped to **Gift: fair market value** and no amount. |

## 7. Common mistakes

**Rows rejected with "The tribute type Honor is not one Open Impact knows".** The tribute type
column still has NPSP's words. Replace them (section 4, step 5) and load the file again: rows
already loaded are matched, not duplicated.

**The same person appears on several records after a payment file.** The donor had no email
address, so **Email exact** had nothing to match or group their payments on, and each payment
created them. Give such donors an email address before the export, or choose **Name plus
postal code**, which the payment file also carries (read its warning on the matching step
first). Either way, check the dry run's "would create" count: a donor who can be matched is
created once however many payments they made, and a couple at one address are told apart by
first name.

**A person's first name changed after a payment file.** Where only one person has the row's
email, a row with a different first name is matched to them and their first name is updated
(see [Importing](importing.md)). Check the dry run's Updated rows before you commit.

**Salesforce warned about duplicates and the import saved the people anyway.** A duplicate
rule set to alert does not stop an import. Run the duplicate scan afterwards
([Duplicates](duplicates.md)). A rule set to **Block** still rejects the row with the rule's
message.

**A tribute appears on every gift of one opportunity.** The opportunity had several payments and
each carried its tribute. Delete the extra tributes, and next time clear the tribute columns on
all but the first payment (section 4, step 6).

**A column you set to Do not load is mapped again next time.** Open Impact's column library
recognises some export headings on its own, for example an account's name, and suggests them
even after you have set them to **Do not load**. The contacts mapping leaves the account name
out on purpose, because it would create an organization for every household. Check the column
step on every load, or delete the column from the file.

## Column reference

Each mapping reads the columns its query in section 4 exports. The headings match whatever
their capitals.

| Column heading | Loads into |
|---|---|
| `Id` | Gift: external ID |
| `npe01__Payment_Amount__c`, `npe01__Payment_Date__c` | Gift: amount, Gift: date |
| `npe01__Payment_Method__c` | Gift: payment method |
| `npe01__Check_Reference_Number__c` | Gift: payment reference |
| `npe01__Opportunity__r.Campaign.Name` | Gift: appeal |
| `...npsp__Primary_Contact__r.FirstName`, `LastName`, `Email`, `MailingPostalCode` | The donor's first name, last name, email and postal code |
| `npe01__Opportunity__r.Account.Name` (organization payments) | The organization's name |
| `...npsp__Tribute_Type__c`, `npsp__Honoree_Name__c`, `npsp__Notification_Recipient_Name__c`, `npsp__Notification_Message__c` | Tribute: type, honoree name, notify (name), message |
| `Salutation`, `FirstName`, `LastName`, `Title`, `Birthdate`, `Email`, `Phone`, `HomePhone`, `MobilePhone`, the mailing address, `HasOptedOutOfEmail`, `DoNotCall` | The person's field of the same name |
| `npe01__HomeEmail__c`, `npe01__WorkEmail__c`, `npe01__AlternateEmail__c` | Personal, work and alternate email |
| `npe01__Preferred_Email__c` | Preferred email (Personal, Work or Alternate, the same words as NPSP) |
| `npsp__Deceased__c` | Deceased |
