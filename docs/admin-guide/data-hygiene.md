# Data hygiene

**Feature:** C-28 Data hygiene console
**Package:** Core
**Iteration:** v0.7

## 1. What it does

**Data hygiene** is the **Data quality** section of [Org Optimizer](org-optimizer.md). It
answers "which of my records need tidying up?" It runs a
short list of checks over your data, shows how many records each one finds, and for each
check offers **Open in Find**, which opens the matching records in Find so you can read them,
export them, or change them.

| Check | Finds |
|---|---|
| **People with no household** | People who are not in any household. |
| **Households with nobody in them** | Households whose member count is zero or empty. |
| **Memberships that name nobody** | Household membership records whose person was deleted. |
| **Addresses that belong to nobody** | Address records whose household, organization or person was deleted. |
| **Default addresses with parts missing** | The address each household, organization or person is mailed at, missing a street, a city or a postal code. |
| **Default addresses that failed verification** | The address each one is mailed at, marked **Failed** by an address verification app. |
| **People with no way to reach them** | Living people with no email, phone, mobile or mailing address. |
| **Deceased people who can still be emailed** | People marked Deceased who have an email and are not opted out of email. |
| **People not changed in 5 years** | People nobody has changed for the number of years you set (5 unless you change it). |

Data hygiene never changes a record. The counts, like everything in Find, are read with your
own access: a record you cannot open is not counted, and a check whose object or field you
cannot see says so instead of showing a number.

## 2. How to turn it on

1. Data hygiene uses the same permission as Find: **Find and Export Records**. The
   **BarnCRM Admin** role has it, and so does the **BarnCRM Find and Export** permission set
   (see [Find and export](find.md)).
2. Open the **Org Optimizer** tab in the BarnCRM app (it used to be called **Data Hygiene**)
   and choose **Data quality**. The checks run as the section opens.
3. Press **Recount** whenever you want fresh numbers. Nothing is saved between visits.

There is one setting: **Years before a person is not changed**, under **General** in
**BarnCRM Settings**. It is 5 unless you change it, and accepts 1 to 20; the settings page refuses
anything outside that and saves nothing ("... takes a number from 1 to 20, so nothing was
saved"). The check's name shows the number in use.

## 3. A five-minute walkthrough (as Maria)

Maria's organization loaded 3,000 people from a spreadsheet last month, with automation
paused for the load. She wants to know what the load left behind.

1. Maria opens the **Org Optimizer** tab and chooses **Data quality**. Nine checks are listed, each with a number. **People
   with no household** says **214**. **Default addresses with parts missing** says **38**. The
   others say **0**.
2. Next to **People with no household** she presses **Open in Find**. The Find tab opens with a
   new saved query of hers, **Data hygiene: People with no household**, already open.
3. The query is filled in: object Contact, columns Name and Created Date, one condition
   (**Account ID is blank**), sorted oldest first, and it has already run. She reads the list.
   They are all from last month's load.
4. She presses **Export to CSV**, works through the file with the volunteer coordinator, and
   adds the people to households (see [Households](households.md)).
5. Back on **Data quality** in Org Optimizer, she presses **Recount**. **People with no household** says **0**.
6. She does the same for **Default addresses with parts missing**: Find lists 38 addresses, each
   with its household or person, and she fills in the missing postal codes.

## 4. The checks

| Check | Exactly what is counted | Why it matters | What to do |
|---|---|---|---|
| **People with no household** | With household membership on the person's account (the simple way): every contact with no account. With membership records (the flexible way): every person, contact or person account, with no current membership (no end date, or one still to come), leaving out a contact whose account is an organization or a household. | A person in no household is left out of household names, greetings, totals and mailings. Most come from a load with automation paused. | Add each person to a household. If **Create a household automatically** is off on purpose, some of these may be your choice. |
| **Households with nobody in them** | Households (record type Household) whose **Member Count** is zero or empty. | An empty household still shows up in lists, reports and mailings. | Add a member, merge it into another household, or delete it (see [Household merge and split](household-merge-split.md)). In an org with Salesforce Nonprofit Cloud households, a household that is also one of those keeps its members in Nonprofit Cloud and can be listed here; the check then carries a note. Never delete such a household: its Nonprofit Cloud household group is deleted with it. |
| **Memberships that name nobody** | Household membership records with neither a contact nor an account: the person was deleted while automation was switched off. | Such a record counts for nobody, but it still sits on the household's related list. | Delete them. They hold nothing but the household and the dates. |
| **Addresses that belong to nobody** | Address records with no household, organization or person: the record they belonged to was deleted. | They are kept on purpose (an address is history), but nobody will ever see them from a record page. | Delete them, or set an owner if the address should be kept. |
| **Default addresses with parts missing** | Default addresses (the one copied to the standard address fields) with no street, no city, or no postal code. | A letter to that address will not arrive. | Fill in the missing part on the address card. Only the default address is checked: older addresses are the record of where mail went, and are left as they are. |
| **Default addresses that failed verification** | Default addresses whose **Verification Status** is **Failed**. BarnCRM never sets this field; an address verification app does. | The verification app could not confirm the address. | Check the address with the person, then correct it. Without a verification app this check always says 0. |
| **People with no way to reach them** | Contacts (people) not marked **Deceased** with no **Email**, **Phone** or **Mobile**, and no **Mailing City** or **Mailing Postal Code**. The mailing fields are where the default address is copied. | Nothing you send reaches them, and they still count in your totals. | Find a way to reach them, or decide whether to keep them. Another email field (personal, work) is not looked at. |
| **Deceased people who can still be emailed** | People marked **Deceased** who have an **Email** and do not have **Email Opt Out** ticked. | A message to someone who has died hurts the family and your organization. | Tick **Email Opt Out** (Bulk update can do it from the Find query). |
| **People not changed in N years** | People whose **Last Modified Date** is older than the years in **Years before a person is not changed** (5 unless set). | Old records nobody looks at may be out of date, or may be candidates for archiving. | Review them in Find. Nothing is archived or deleted for you. |

In an org that uses membership records, **Open in Find** for **People with no household** lists
the contacts that have no current membership (Find's **Has no related records**, see
[Find](find.md), section 7.1), leaving out a contact whose account is a household or a person
account. The date "today" is written into the query when you press **Open in Find**, so press
it again for an up-to-date list. The count and the list can differ, and the check says so:
people kept as person accounts are in the count but not in the Find list, because Find lists one
kind of record at a time; and the count leaves out people who have been erased, which Find
cannot do because people who run Find cannot read the erasure records, so it may list an erased
contact. Health Check links the first five of the people counted.

Each count stops at 2,000 and then says **More than 2,000**, the same as the most rows Find
shows at once. Find's export reads every matching record.

## 5. How Open in Find works

1. Press **Open in Find** next to a check. BarnCRM saves the check's query as one of your own
   saved queries, named **Data hygiene:** followed by the check's name, not shared with anyone,
   and opens the Find tab.
2. Find opens that query with its object, columns, conditions and sort filled in, and runs it.
   The list is ready to read, **Export to CSV**, or change. The query also stays under
   **Saved queries** for next time.
3. Pressing **Open in Find** again later puts that saved query back to the check's own query,
   so your copy always matches what the console counted. To keep a version you changed, use
   **Save as** in Find and give it another name.

Every query is built for your org when you press the button: its field names, its membership
mode and its record type are read from the org at that moment, so it never goes out of date.
Nothing about the checks is stored in the package as a record you could edit or delete.

## 6. Data hygiene and Health Check

They answer different questions:

| | Health Check | Data hygiene |
|---|---|---|
| Asks | Is BarnCRM set up the way it should be? | Which records need tidying up? |
| Looks at | Settings, access, automation, schedules, what is installed, plus two headline data findings (people with no household, empty households). | Your records only, with more checks, including addresses and membership records. |
| Shows | A finding with a severity, what to do, and up to five links. | A count per check, and every matching record in Find. |
| Fixes | Some findings have a fix button for a setup problem with one right answer. | Never changes anything. You work through the records in Find, by export, or with Bulk update. |

The two counts for people with no household are the same question asked the same way, but
Health Check reports it only while **Create a household automatically** is on, and Data
hygiene reports it always. For empty households, Health Check reads the memberships themselves
and Data hygiene reads **Member Count**, so that the check can open in Find. They disagree
only when a Member Count is out of date, for example after a load with automation paused, and
saving the household again puts it right.

## 7. Common mistakes

- **Expecting the console to fix things.** It finds and lists. Deciding what a person with no
  household should become is a question only your organization can answer.
- **Editing the Data hygiene query and expecting it to stay.** **Open in Find** puts it back to
  the check's own query. Use **Save as** for your own version.
- **A check says "You cannot see" a field or an object.** The counts use your own access. Ask
  whoever manages access in your org, or run it as a BarnCRM Admin.
- **A different number from a colleague.** Same reason: each person counts what their own
  access allows.
- **Deleting an empty household that something else still points at.** Gifts, addresses or
  other records may still name it. Merge it into the right household instead of deleting it.
- **Deleting a household that is also a Nonprofit Cloud household.** It looks empty here
  because its members are kept by Nonprofit Cloud. Deleting it deletes its Nonprofit Cloud
  household group too. Leave it to Nonprofit Cloud's own tools.

## 8. What Data hygiene does not do (yet)

Checking that an email address is well formed is left to Salesforce: an Email field refuses
an address that is not one. Checking that a household's **Member Count** is up to date needs
the members counted again, which a query cannot do; saving the household puts it right (see
section 6).

Checking whether a household's name still matches the naming rule needs every name worked out
again, which is not a question a query can ask; it is not offered. Checks on related records
("households with no gifts") are built in Find with **Has no related records** (section 7.1 of
[Find](find.md)); only the one above is a ready-made check. Changing many records at once is
**Bulk update** (C-35), which starts from a Find query.

## Field reference

Data hygiene adds no object and no field. It reads the fields named above and writes one
**Saved Query** per check you open, owned by you (see [Find and export](find.md)).
