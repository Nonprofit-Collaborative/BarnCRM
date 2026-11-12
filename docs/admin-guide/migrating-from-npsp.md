# Migrating From NPSP

**Package:** Core and Giving | **Iteration:** v0.5

## 1. What It Does

If your donors and gifts are in the Nonprofit Success Pack (NPSP), BarnCRM ships three
ready-made import templates that read NPSP's own exports: your contacts, and the payments your
donors made, from people and from organizations. You export each file with Data Loader or
Workbench, without renaming a column, and load it through the **Import** tab like any other
file, with a preview first and an undo afterwards.

The templates only name columns. Nothing in BarnCRM depends on NPSP being installed.

If BarnCRM is installed in the same org as NPSP, start by adopting NPSP's households in place
([Adopting Your NPSP Households](npsp-households.md)) rather than loading the contacts file:
your people are already there. Then set NPSP's Account Model to One-to-One or Individual and
turn on Households, in that order: BarnCRM does not let Households on while NPSP
households are in use.

## In-Org Migration Kits

When NPSP is installed in the same org as BarnCRM, you do not need files at all. The
[Migration Assistant](migration-assistant.md) reads NPSP's records directly, step by step, with
the same preview, results and undo as a file import, and checks that the numbers match. Open
**BarnCRM Settings**, **Integrations**, find **Nonprofit Success Pack (NPSP)** and click the
kit's **Start Migration** button. Run the kits in the order listed.

**NPSP People and Addresses** (BarnCRM Core):

| Step | What it does |
|---|---|
| Adopt NPSP Households | Opens BarnCRM Settings, where **Adopt NPSP Households** makes your NPSP household accounts BarnCRM households in place ([Adopting Your NPSP Households](npsp-households.md)). Click **Mark Done** when it has finished. |
| Relationships | Copies each NPSP relationship once. NPSP keeps both sides of a relationship as two records; the kit reads only the side a person entered and leaves the other side to BarnCRM, which creates it for you. Both people are the same contacts. NPSP types become BarnCRM's (Husband and Wife become Spouse, Coworker becomes Colleague, Employer and Employee become Employer contact); a type BarnCRM does not have becomes Other. |
| Affiliations | Copies each link between a person and an organization, with its role, status, dates, description and primary. |
| Household Addresses | Copies each NPSP address onto its household, both street lines in one, with its type (Vacation becomes Seasonal), default, seasonal months and days, and verified. |

The retire checklist then reminds you to stop NPSP creating the other side of relationships,
affiliations, household addresses and household names, so the two apps never both do it.

**NPSP Funds, Levels, Recurring Donations** (BarnCRM Giving):

| Step | What it does |
|---|---|
| Funds | Copies each General Accounting Unit as a fund with its name, description and active flag. A unit whose name is already a BarnCRM fund makes a second fund of that name, so check **Funds** in the preview first. |
| Donor Levels | Copies each NPSP level as a donor level with its name, description, minimum and maximum amounts and active flag. |
| Recurring Donations of People | Copies each recurring donation of a contact as a recurring commitment of that person: amount, start (NPSP's next payment date, or the date established when there is none, so no run of overdue payments is made), frequency (1st and 15th becomes Every two weeks; Monthly every 3 months becomes Quarterly, every 6 Twice a year, every 12 Yearly; any other period not in BarnCRM becomes Monthly) and status (Lapsed becomes Paused, Closed becomes Cancelled; a donation with no Status uses its Open Ended Status, Open becoming Active). |
| Recurring Donations of Organizations | The same for recurring donations of an organization, as a commitment of that account. |
| Engagement Plans | Copies each NPSP engagement plan template as an active stewardship plan template with its name and description, started by hand (**Manual**). Loading again updates the same template. |
| Engagement Plan Tasks | Copies each task of those templates as a step of its stewardship plan: the subject, days after the start (also the step order), priority (Medium becomes Normal), comments, and the assigned user (**Specific user**) or else the record owner. |
| Levels, Engagement Plans and Rollups Parity | The parity report, done on the **Stewardship Plans** tab. Its check counts your active NPSP levels and engagement plan templates, and how many have a BarnCRM counterpart (a donor level of the same name, a stewardship plan template copied from it). Read the table below, set up what you still need, and click **Mark Done**. |

The kit does not copy NPSP's open installment Opportunities: BarnCRM schedules the payments of
each commitment itself. Gifts already received come across with the next kit. The retire
checklist reminds you to stop NPSP's recurring donation and levels jobs, make the General
Accounting Units inactive, stop applying NPSP engagement plans, and point payment processors at
BarnCRM.

### Parity Report: Levels, Engagement Plans and Rollups

What NPSP does in these three areas, and where it lives in BarnCRM after the kits run:

| NPSP | BarnCRM | What to do |
|---|---|---|
| Levels on contacts or accounts, with a minimum and maximum | Donor levels, one ladder ([Donor Levels](donor-levels.md)) | Copied by **Donor Levels**. Choose what the ladder is measured on in Giving settings. |
| A level's source field (any rollup field) | The ladder's measure: total giving, giving this or last fiscal year, or largest single gift | Pick the measure closest to your NPSP source field. A level on another field has no counterpart. |
| More than one ladder (contacts and accounts, or several fields) | One ladder | Keep the main ladder; recreate others as a rollup plus a report if you need them. |
| Previous level field | **Previous donor level** on the person | Kept by BarnCRM from now on; NPSP's history is not copied. |
| A level that applies an engagement plan | A stewardship plan started by hand or by **First gift**, **Gift received** or **Commitment started** ([Stewardship Plans](stewardship-plans.md)) | Start the copied plan from those events, or by hand when a donor reaches a level. |
| Engagement plan templates and tasks | Stewardship plan templates and steps | Copied by **Engagement Plans** and **Engagement Plan Tasks**. |
| Dependent tasks, skip weekends, reschedule, reminders, send email | Steps by days after the start | Not copied; set due dates and reminders on the tasks a plan makes. |
| Engagement plans already applied to records, and their open tasks | Plans started in BarnCRM | Not copied: the open NPSP tasks stay as ordinary tasks. |
| Customizable rollups | Rollup Builder ([Rollups](rollups.md)) | The **NPSP Customizable Rollups** kit copies them and checks each. What Rollup Builder cannot express (soft credit, contact role and payment paths, fiscal years, Years Donated, Donor Streak, Best Year, more than one year back, filter rules on another object) stays in NPSP, named with its reason. |

**NPSP Gifts and Soft Credits** (BarnCRM Mirror, because it reads Opportunities and Campaigns).
Run it after the two kits above, so the people, households and funds are already there:

| Step | What it does |
|---|---|
| Appeals | Copies each Campaign as an appeal with its name, description, dates and active flag. An appeal that already holds the Campaign's ID (from Campaign sync) is updated, not made twice. |
| Gifts | Copies each won Opportunity as one gift: the amount and close date, the donor by record ID (the primary contact of an individual's gift, else the organization), the payment method and check number of its first paid payment (Other when it has none), its appeal, its General Accounting Unit allocations as the gift's funds (by fund name, so run the Funds step first), and its tribute (Honor becomes In honor of, Memorial becomes In memory of). The Opportunity's record ID becomes the gift's external ID and **Opportunity ID**, so loading again matches instead of duplicating, and the [Opportunity Mirror](opportunity-mirror.md) never copies it again in either direction. |
| Soft Credits | Copies each contact role of a won Opportunity as a soft credit on its gift, except the donor's own role, household members (BarnCRM credits those itself) and the Honoree and Notification Recipient roles (the gift's tribute carries those; a role renamed in NPSP Settings is copied as Other). Soft Credit and other NPSP roles BarnCRM does not have become Other, keeping their name; a partial soft credit keeps its amount, any other credit is for the whole gift. |
| Contacts of Organization Gifts | Gives the primary contact of each organization's won Opportunity a soft credit on its gift, as NPSP does. |
| Account Soft Credits | Copies each NPSP account soft credit as a soft credit of that organization on the gift. |

Before you run it:

- Install BarnCRM Mirror and give yourself the **Salesforce Records Sync** permission set on the
  Access page (it lets you write each gift's Opportunity ID and each appeal's Campaign ID).
- Leave **Opportunity mirror direction** at **Off** while the gifts load, so no Opportunity is
  written to. Switch it on afterwards if you want.
- Switch **Send gift acknowledgments** off (BarnCRM Settings, Giving, Acknowledgments) so donors
  are not thanked again for old gifts, and switch it back on after the Gifts step is done.

What the gifts step leaves to you, each shown in the preview so you can correct the row on
screen: a gift split across more than five funds (the first five are read, so the parts no longer
add up), allocations that do not add up to the Opportunity's amount, a payment method BarnCRM does
not know, and a fund name two funds share. An Opportunity with several paid payments becomes one
gift for its whole amount, dated at its close date. Pending pledges (open Opportunities) and their
unpaid payments stay in NPSP: record open pledges as commitments ([Commitments](commitments.md)).
NPSP's separate Tribute records, beyond the one on the Opportunity, are not copied.

## 2. How to Turn It On

BarnCRM brings the contacts template, and the Giving module brings the two payment templates.
Each package adds its templates when it is installed, and an upgrade adds any template a later
version ships, so the **Import** tab normally lists them already. An upgrade never changes a
template you have edited. A shipped template you deleted comes back on the next upgrade: switch
it off instead if you do not want it in the list.

If one is missing (an install that logged a problem, for example), add it from Health Check:

1. Open the **BarnCRM Admin** app, click **BarnCRM Settings** and choose **Health**.
2. The report opens (click **Re-Run** if it is from earlier). A finding reads "3 shipped
   import templates are missing" (a higher number if other shipped templates are missing too)
   and names them.
3. Select **Restore Import Templates**. Your own templates, and any shipped template you have
   edited, are not touched.
4. Open the **Import** tab. The list now has **NPSP: Contacts**, **NPSP: Opportunities and
   Payments** and **NPSP: Organization Payments**.

Before loading gifts, create in BarnCRM every appeal the gifts name, with the same names
as your NPSP campaigns (see [Appeals](appeals.md)), and a default fund (see [Funds](funds.md)).
A gift naming an appeal BarnCRM does not have is rejected in the preview, naming it.

## 3. A Five-Minute Walkthrough (as Maria)

The three sample files in [samples](samples/) are small exports in exactly the shape the steps
in section 4 produce. Create a default fund called **General Fund** and an appeal called
**Year End 2024** first.

1. Open the **Import** tab, select **NPSP: Contacts**, then **Next**, and upload
   `npsp-contacts.csv`. Every column is already mapped: the home email to the personal email,
   the work email to the work email, the preferred email to the preferred email, and so on.
2. Preview, then import. Ana Okafor and Robert Hale are created, each with a household of their
   own. Robert is marked deceased and do not call.
3. Import `npsp-payments.csv` with **NPSP: Opportunities and Payments**. Leave donation matching
   at **Match or create**. The preview says 2 rows would create a gift and 1 would be rejected:
   "The tribute type Honor is not one BarnCRM knows. Use one of: In honor of, In memory
   of."
4. Import these rows. Open Ana Okafor: she has a gift of 150.00 by Card with the appeal Year End 2024, and
   a gift of 50.00 by Check, reference 3312, in memory of Grace Okafor. She was found by her
   email, not created again.
5. In the file, replace `Honor` with `In honor of`, and load it again. The two gifts already
   loaded are matched, not duplicated, and the third is created with its tribute.
6. Import `npsp-organization-payments.csv` with **NPSP: Organization Payments**. Hillside Rotary
   Club is created as an organization and gives one gift of 500.00.

## 4. Moving Everything, Step by Step

Do it in this order. People come before gifts because the contacts file carries each person's
full details (address, phones, preferences), which a gift file does not. A donor the gift file
names on several rows is created once either way, but only with the few details a gift row
has. With the people already loaded, every gift row finds its donor by email. An export of up
to 500,000 rows can be previewed as one file; split anything larger.

1. **Appeals and funds.** Create them in BarnCRM by hand, with the names your NPSP
   campaigns and general accounting units have. There is no import for them yet.
2. **Contacts.** Export them with this query and load the file with **NPSP: Contacts**.

   ```sql
   SELECT Salutation, FirstName, LastName, Title, Birthdate, Email, npe01__HomeEmail__c,
       npe01__WorkEmail__c, npe01__AlternateEmail__c, npe01__Preferred_Email__c, Phone,
       HomePhone, MobilePhone, npe01__WorkPhone__c, npe01__PreferredPhone__c, MailingStreet, MailingCity, MailingState, MailingPostalCode,
       MailingCountry, npsp__Deceased__c, HasOptedOutOfEmail, DoNotCall
   FROM Contact
   ```

3. **Payments from people.** A payment is money received, with its method and check number, so
   each paid payment becomes one BarnCRM gift. An opportunity paid in three payments
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

   Load it with **NPSP: Opportunities and Payments**.
4. **Payments from organizations.** The same query with the organization's name in place of
   the four primary contact columns, loaded with **NPSP: Organization Payments**.

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
   - Payment method: BarnCRM reads Cash, Check, Card, ACH, Stock and In-kind, plus common
     words such as "Credit Card" and "EFT". Any other value is rejected in the preview, naming
     it and the values to use.
6. **One tribute per opportunity.** A tribute belongs to the opportunity, so every payment of
   it carries the tribute. Where an opportunity has several payments, clear the four tribute
   columns on all but its first payment (the file is sorted so they sit together).
7. **Funds, if you use them.** The payment export does not say which fund a gift went to, so
   every gift goes to your default fund (section 6 says how to add a fund column).
8. **Recreate what the templates do not load** (section 6).

In Data Loader, choose **Export**, pick the object named after `FROM` (Payment for the payment
queries), and paste the query into the query box. In Workbench, choose **Queries**, **SOQL
Query**, paste it, and choose **Bulk CSV**. Before the full export, add `LIMIT 5` to a query
and compare the rows with the records they came from.

Check that every closed won gift has a payment:
`SELECT COUNT() FROM Opportunity WHERE IsWon = true AND npe01__Number_of_Payments__c = 0`. If
the count is not 0, those gifts were made while payments were switched off in NPSP and are not
in the payment export. Load them with the **Generic Gift List**.

Check that every paid payment has an account: the two payment queries select on the
opportunity's account, so a payment whose opportunity has none is in neither file.
`SELECT COUNT() FROM npe01__OppPayment__c WHERE npe01__Paid__c = true AND npe01__Opportunity__r.AccountId = null`.
If the count is not 0, give those opportunities an account in NPSP before the export, or export
them with the people query, its last line changed to
`AND npe01__Opportunity__r.AccountId = null`, and load that file with **NPSP: opportunities
and payments** as well.

## 5. Why Three Templates and Not One

A template remembers the columns of the last file loaded with it, so one template serves one
file shape. The shapes differ in ways that matter:

- **Contacts and payments are separate files** because a gift file cannot carry a person's full
  details without repeating them on every gift.
- **Payments, not opportunities.** A payment says when the money came, how, and the check
  number. An opportunity paid in several payments is several gifts in BarnCRM, and a
  pledge's unpaid payments are not gifts at all.
- **Payments from organizations have their own file** because a column that makes the donor an
  organization would make every person in the same file an organization too.

## 6. What Does Not Come Across Yet

These are not loaded by the three templates. Each has what to do in the meantime.

| Not loaded | What to do meanwhile |
|---|---|
| Households and who is in them | When BarnCRM is installed in the NPSP org itself, do not load contacts at all: adopt NPSP's households in place ([Adopting Your NPSP Households](npsp-households.md)), which keeps every family and its people as they are. When you load files into another org, each contact gets a household of their own. Merge the households of people who live together ([Household merge and split](household-merge-split.md)), or load couples in one row with the second person's columns mapped to **Contact 2** ([Importing](importing.md), section 4). Household names are made by BarnCRM's naming. |
| Relationships and affiliations | In the NPSP org itself, the **NPSP People and Addresses** kit copies them ([In-Org Migration Kits](#in-org-migration-kits)). From files, no ready-made template ships for them. After the people and organizations are loaded, load each as a file of its own with **One Kind of Record** ([Importing](importing.md), section 9), naming each person and organization by Salesforce record ID or by name. Or enter the ones you need by hand ([Relationships](relationships.md), [Affiliations](affiliations.md)). |
| Recurring donations and their schedules | No import yet. Create each active recurring gift by hand as a commitment ([Commitments](commitments.md)) before loading payments. With **Match or create**, a payment dated near one of its scheduled payments pays it; older payments load as gifts on their own. |
| General accounting unit allocations | In the NPSP org itself, the **NPSP Gifts and Soft Credits** kit copies them ([In-Org Migration Kits](#in-org-migration-kits)). From files, every gift goes to the default fund. For opportunities with one allocation, export `SELECT npsp__Opportunity__c, npsp__General_Accounting_Unit__r.Name FROM npsp__Allocation__c`, add `npe01__Opportunity__c` to the payment query, and fill a new column headed `Fund` from the allocation file with a lookup on the opportunity. Delete the opportunity column before loading, and check on the column step that `Fund` reads **Gift: fund**. |
| Soft credits (contact roles, partial and account soft credits) | In the NPSP org itself, the **NPSP Gifts and Soft Credits** kit copies them. From files, a soft credit loads only on the same row as a new gift, and NPSP exports them separately. Credits between household members are made automatically; add others by hand ([Soft credits](soft-credits.md)). |
| More than one tribute on a gift | Only the tribute on the opportunity loads. Add others by hand ([Tributes](tributes.md)). |
| Additional and seasonal addresses | In the NPSP org itself, the **NPSP People and Addresses** kit copies every household address, seasonal ones included. From files, only the mailing address loads. Add others by hand ([Addresses](addresses.md)). |
| Written-off and unpaid payments | The exports take paid payments only. Refunds are recorded in BarnCRM after the gift is loaded ([Refunds](refunds.md)). |
| An organization's details | A payment file creates an organization with its name only. Add its address and phone by hand. |
| In-kind gifts | Their payments have no payment method, so the rows are rejected with "The gift has no payment method. Map a column to it, or give the template a default payment method." Load them with the **Generic Gift List**, the value mapped to **Gift: fair market value** and no amount. |

## 7. Common Mistakes

**Rows rejected with "The tribute type Honor is not one BarnCRM knows".** The tribute type
column still has NPSP's words. Replace them (section 4, step 5) and load the file again: rows
already loaded are matched, not duplicated.

**The same person appears on several records after a payment file.** The donor had no email
address, so **Email exact** had nothing to match or group their payments on, and each payment
created them. Give such donors an email address before the export, or choose **Name plus
postal code**, which the payment file also carries (read its warning on the matching step
first). Either way, check the preview's "would create" count: a donor who can be matched is
created once however many payments they made, and a couple at one address are told apart by
first name.

**A donor was created twice after a payment file.** A row is matched only to a person with
the same first name, so a payment row spelling the donor's first name differently from your
org ("Bob" for Robert, "J." for John, an accent added or dropped) creates a new person
rather than renaming the one you have (see [Importing](importing.md)). Check the preview's
"would create" count before you import, and fix the spelling in the file, or merge afterwards.

**Salesforce warned about duplicates and the import saved the people anyway.** A duplicate
rule set to alert does not stop an import. Run the duplicate scan afterwards
([Duplicates](duplicates.md)). A rule set to **Block** still rejects the row with the rule's
message.

**A tribute appears on every gift of one opportunity.** The opportunity had several payments and
each carried its tribute. Delete the extra tributes, and next time clear the tribute columns on
all but the first payment (section 4, step 6).

**A column you set to Do not load is mapped again next time.** BarnCRM's column library
recognises some export headings on its own, for example an account's name, and suggests them
even after you have set them to **Do not load**. The contacts template leaves the account name
out on purpose, because it would create an organization for every household. Check the column
step on every load, or delete the column from the file.

## Column Reference

Each template reads the columns its query in section 4 exports. The headings match whatever
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
| `npe01__WorkPhone__c` | Work phone |
| `npe01__PreferredPhone__c` | Preferred phone (Home, Mobile, Work or Other, the same words as NPSP). Any other value, such as "Household", loads as an empty Preferred Phone, so the ordinary Phone is left as it was exported |
| `npsp__Deceased__c` | Deceased |
