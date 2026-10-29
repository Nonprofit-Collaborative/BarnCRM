# Duplicates

## What It Does

Finds people and households that are in your database twice, and helps you deal with them one
pair at a time, on the **Duplicate Matching** tab. Salesforce does the finding, with the duplicate rules every org starts with:
it warns the person typing that somebody similar already exists. What Salesforce does not do
in most editions is look through the records you already have, so a spreadsheet imported last
year is never checked against itself. BarnCRM adds that scan, lists every pair on one page,
and puts the household merge one click away.

Nothing is ever merged or deleted for you. Every merge is a pair you looked at and confirmed.

Salesforce's rules only compare fields on the person or household itself. The scan also looks
at **match sources**: related records such as contact point emails, phones and addresses, and
BarnCRM addresses. Two people who share an email held only on a contact point email record are
listed too, with a line saying why, for example "Same email on Contact Point Email". Match
sources are listed, added, deactivated and tried out in the tool's **Matching Logic** area;
see [Matching Logic](#matching-logic).

## How to Turn It On

There is nothing to install, but on a new install the **Duplicate Matching** feature is off
until you turn it on: choose **Turn On** in the **Duplicate Matching** row in **BarnCRM
Settings**, **General** (or leave it ticked in first-run setup); see
[BarnCRM Settings](barncrm-settings.md). While it is off the **Duplicate Matching** tab is
hidden for everyone. Salesforce switches on its standard duplicate rules
for people and accounts in every new org, and BarnCRM uses them. There is one permission
step, because of a Salesforce licensing rule:

**Who can review duplicates.** Salesforce keeps possible duplicates in records called duplicate
record sets, and gives access to them only to users with a **Sales Cloud or Service Cloud
license**. No other license can have it, Salesforce Platform included. So BarnCRM puts that
access in its own permission set, **BarnCRM Duplicate Review**, which is in no role. In BarnCRM
Settings, open **Access** and, under **Extra Permissions**, give **BarnCRM Duplicate Review** to
each person who will review duplicates. Salesforce refuses the assignment for a user
without one of those licenses. A holder who is not an administrator also gets the **Duplicate
Matching** tab with its **Review** area, which they can read; scanning, dismissing and
merging there stay with BarnCRM Admin. If nobody in your org has one, duplicate rules still warn people
as they type, but nobody can review or merge suggestions: not on this panel, and not on the
**Potential Duplicates** card on a contact's page, which reads the same records and shows a
Platform user nothing usable.

**Who sees the tab.** BarnCRM gives the **Duplicate Matching** tab automatically, while the
feature is on, to holders of **BarnCRM Admin**, **BarnCRM Duplicate Review** and **BarnCRM
Metadata Admin** (see [Access](access.md)).

1. Open the **BarnCRM Admin** app and choose the **Duplicate Matching** tab (someone without
   that app, such as a Duplicate Review holder, finds the tab in the App Launcher). (In **BarnCRM
   Settings**, the **Duplicate Matching** section's **Duplicate Matching** row has an **Open
   this page** button that brings you here too.)
2. The **Review** area opens first.
3. Under **Duplicate Rules** each rule for people and accounts is listed with On or Off. At
   least one should say On. If none does, see Common mistakes below.
4. Choose **Scan for Duplicates**. The scan looks through the people and households you
   already have. It runs in the background and can take a while in a large database.
5. When it finishes, the line under the button says what the last scan did, for example
   "Duplicate scan of Contact, Account finished: 3 new possible duplicates recorded." If part of
   the database could not be checked, the line is red and says how many batches of up to 50
   records could not be checked; see Common mistakes below.

Run the scan again after a large import: Salesforce checks a record against the others when
it is saved, but an import that saved past a warning leaves the pair for the scan to find.

**The review list.** The **Review** tab and **Possible Duplicates** both show how many pairs
are waiting (for example **Review (40)**, or 50+ when there are more than the list reads at
once), then the first 10 pairs, newest first. Each pair is one card: why it was suggested and
its buttons at the top (**Merge Households** is the main button on a household pair), then the
records side by side. Each side shows the record's name (a link to it), Person or Household,
and the fields compared: for a person the email, phone, mailing street, city and postal code,
and household; for a household the billing street, city and postal code, and phone. Only
fields you can read are shown. A value that is not the same on both sides carries a
**Different** badge, so you see at a glance what sets the two apart. On a narrow screen the
sides stack. **Show More** adds the next 10, and the line
under the list says how many are showing. The note on merging two people is shown once, above
the list, not on every pair. **Not a Duplicate** and **Merge Households** open their short
form inside the pair's own card. When nothing is waiting the list shows **No Possible
Duplicates** with a reminder to scan after a large import.

### Settings

In **BarnCRM Settings**, the **Duplicate Matching** section holds the tool's settings: a note
on the one Setup step (keep the duplicate rules active, give reviewers Duplicate Review) and
the **Duplicate Matching** row, whose **Open This Page** button opens the tab. The scan has
no options to set: it always checks every person and household with your active duplicate
rules and your active match sources.

### Matching Logic

The **Matching Logic** area of the **Duplicate Matching** tab lists the match sources: the
related records the scan and imports look at, alongside your Salesforce duplicate rules, to
tell that two people or two households are the same. The rules themselves are listed, read
only, in **Review**, with a link to change them in Setup.

Who sees it: anyone with **Manage BarnCRM Settings** (BarnCRM Admin) or the **BarnCRM
Metadata Admin** permission set. Adding, changing, deactivating and activating a source
needs **BarnCRM Metadata Admin**, because saving one changes the org's metadata; without it
the list is read only, and **Try a Value** still works. If BarnCRM was installed as a
package, saving also needs **Deploy Metadata from Non-Certified Package Versions via Apex**
turned on in Setup, **Apex Settings**; see [Custom metadata](custom-metadata.md#how-to-turn-it-on).

The area opens with one line on what match sources are; the help icon beside it says how they
work with your duplicate rules and how saving works. Each source is a card: its name, a
**Shipped with BarnCRM** badge where it applies, and one line saying what it compares, for
example "Email Address on Contact Point Email, compared as Email". With BarnCRM Metadata Admin
the card has an **Active** switch; without it, an **Active** or **Inactive** badge. **Show
Details** on a card lists, in words:

- **Object**: the related object, for example Contact Point Email.
- **Field compared**: the field holding the value: the email, the phone number, or the street.
- **Postal code field**: address sources only; the postal code compared with the street.
- **Belongs to**: a person, a household (or person account), or either.
- **Through the lookup**: the field linking the value to its person or household.
- **How values are compared**: Email, Phone or Address, with what is ignored.

A source that cannot work in this org (its object
or a field is missing, or you cannot read it) says **Not used in this org** and is skipped.

BarnCRM ships six sources, marked **Shipped with BarnCRM**:

| Source | Object | Field compared | Through the lookup | Compared as |
|---|---|---|---|---|
| Contact Point Email | Contact Point Email | Email Address | Parent | Email |
| Contact Point Phone | Contact Point Phone | Telephone Number | Parent | Phone |
| Contact Point Address | Contact Point Address | Street, with Postal Code | Parent | Address |
| Address (person) | Address | Street, with Postal Code | Contact | Address |
| Address (household) | Address | Street, with Postal Code | Account | Address |
| Address (person account) | Address | Street, with Postal Code | Person Account | Address |

The contact point objects exist only in some orgs (Nonprofit Cloud has them). Where an
object is missing, its source does nothing; nothing breaks. A shipped source can be
deactivated and activated again, but not changed; upgrades keep it up to date and never
overwrite what you added.

How values are compared:

- **Email**: spaces at either end are ignored, and capitals do not matter.
- **Phone**: only the digits count, so (555) 123-4567 and 555.123.4567 match. A North
  American number written with a leading 1 matches the same number without it. A number with
  fewer than seven digits is ignored.
- **Address**: the street, with capitals, punctuation and extra spaces ignored and common
  words shortened (Street and St, Avenue and Ave match), together with the postal code
  (spaces ignored; a ZIP+4 counts as its first five digits).

A contact point record can belong to a person, an account, or a Salesforce **Individual**
(the privacy record behind a person). A person or an account is used as it is; an Individual
counts as every person who carries it, contacts and, where your org has person accounts,
person accounts too. A record that belongs to anything else is skipped.

**Add a source.** Choose **Add**: the form opens in a window over the page (Escape or
**Cancel** closes it). Fill in **Name**, then the object's API name under **Object** (for
example `Volunteer_Profile__c`) and choose **Find Fields**: the
**Field compared** and **Through the lookup** lists then offer only the fields that can
work (text, email or phone fields Salesforce can search on, and lookups to a contact, an
account or an Individual). Choose **How values are compared**; for **Address**, also choose
the **Postal code field**. **Save** checks the source against the org and refuses anything
that cannot work, saying why in the window, which stays open. Once the source is accepted the
window closes. Saving takes about a minute, because Salesforce applies it in the background:
the area says "Saving", then "Saved" and lists the source. If you leave before then, choose
**Check Again** when you come back. A source you added has **Edit** as well, which opens the
same window with the source's values filled in.

**Deactivate a source.** Turn off the **Active** switch on its card; turning it on brings the
source back. The switch moves once Salesforce has applied the change (about a minute).
Salesforce does not let an app delete custom metadata, so a source is deactivated instead.

**Try a value.** Choose **Try a Value** on a card, type an email, phone or street (and, for
an address, the postal code), and choose **Try**. The area shows the value as the source
compares it ("Compared as: 12 n main st|02139") and lists the people and households you can
see that hold it. Nothing is saved. A value too short to compare says so.

A value shared by more than ten people or households, such as an office's main number, is
ignored: it says nothing about whether two of them are the same.

Each lookup reads at most 5,000 records. When a lookup reaches that limit, or a scan or import
step has used most of what Salesforce allows in one go so a source is skipped, the Error Log
gets one warning naming the source, and the values that lookup found are not used, since some
of the records holding them were not read. Some duplicates may then be missed until the next
scan. A source whose values are very common is a candidate to deactivate.

## A Five-Minute Walkthrough

Start with the sample data loaded (see [sample-data.md](sample-data.md)). Create one duplicate
on purpose: open any sample person, note their email address, and create a new contact with
the same first name, last name and email. Salesforce warns you that a similar record exists;
choose to save anyway.

1. Open the **Duplicate Matching** tab. The **Review** area opens.
2. Choose **Scan for Duplicates**. You see "Scan started. It runs in the background, and
   suggestions appear here as they are found."
3. Wait a minute and refresh the page. Under **Possible Duplicates** you see the pair you made,
   each person with their email address.
4. Choose the person's name to open their record. On the right of the page the **Potential
   Duplicates** card names the other record. Choose **View Duplicates**, then **Compare and
   merge**, pick the values to keep, and confirm. Salesforce allows this only to people with
   Delete on contacts (on accounts, for person accounts): BarnCRM Admin has it, and the staff
   roles deliberately do not, so staff ask an admin to merge two people. Merging two
   households needs no Delete permission (see
   [Household merge and split](household-merge-split.md)). This is Salesforce's own merge, and it keeps
   the activities and files of both (and, with Giving, their gifts). BarnCRM then adds the
   kept person to any household the other one belonged to, and recalculates their totals
   straight away. A household the other person leaves empty is kept, not deleted, because
   records can still point at it: merge it into the kept person's household with **Merge Households** (step 6).
   Within a minute or so BarnCRM also tidies the kept person in the background: one default
   address stays (see [Addresses](addresses.md)), a relationship the two records had with each
   other is removed, so is a second copy of a relationship both had with the same person, and
   their primary affiliation is chosen again.
5. Back on the Duplicates panel, refresh. The pair is gone.
6. If the scan found two households, choose **Merge Households** on the pair. You see the two
   side by side, the fields where they disagree, and which one is kept. Choose the household to
   keep and choose **Merge these two**. You see "The two households are now one."
7. For a pair that is not the same person, for example twin sisters at one address, choose
   **Not a Duplicate**, type a short reason, and confirm. You see "Noted. This pair will not be
   suggested again." Scan again and check that the pair does not come back. It stays off the
   panel even when a duplicate rule reports the pair again as someone saves one of the two.
   A suggestion that names three or more records (one a duplicate rule wrote as someone saved)
   is dismissed as a whole: every pair in it is noted. If two of them are in fact the same
   person, merge those first, then dismiss the rest.

### Pairs Found Through Related Records

Each pair on the list says why it is there: the name of the duplicate rule that found it, or,
for a pair a match source found, what the two share and where ("Same address on Address
(person)"). A pair both a rule and a source found is listed once, under the rule. Review,
merge and dismiss these pairs exactly like the others; a dismissed pair is not proposed again
by either.

Limits to know:

- **A match source pair still needs an active duplicate rule for the same kind of record.**
  Salesforce will not store a suggestion without one. With no active rule for people, the scan
  does not run its people pass at all, sources included. Salesforce's own **Duplicate Record
  Sets** tab, and any report on it, shows a match source pair under that active rule's name,
  because Salesforce makes every suggestion name a rule; the reason is shown only here, on the
  review list.
- **A value shared by more than ten people or households is ignored**, such as an office's
  main number, because it says nothing about whether two of them are the same.
- **People in the same household are not paired by a shared phone or address**, since that
  is what living together looks like. A shared email still pairs them.
- **Pairs are proposed between contacts or between households.** A person stored as a person
  account is never proposed by the scan, by a rule or by a source.
- **Each lookup reads at most 5,000 related records.** If a source's values are so common
  that a lookup reaches that limit, some pairs are missed and a warning naming the source is
  written to the Error Log.

## Common Mistakes

**The panel says no duplicate rule is switched on, and the scan button is refused.** The scan
asks Salesforce to apply your active duplicate rules to the records you already have. With no
active rule there is nothing to apply, and reporting a clean database would be wrong. Choose
**Open Duplicate Rules in Setup**, open **Standard Contact Duplicate Rule** and **Standard
Account Duplicate Rule**, and choose **Activate** on each. This is the one Setup step, and only
orgs that switched the rules off need it.

**The scan finds nothing in a database you know has duplicates.** The standard rules match on
a similar name together with the same email, phone or address. People with no email, phone or
address match on nothing. Fill those in, or ask whoever manages your Salesforce to widen the
matching rule in Setup, and scan again.

**An organization pair never appears.** The panel shows people and households only. Merge
organizations with Salesforce's own tools. A scan checks households only when an account rule
that compares organizations and households is switched on; a person account rule alone does
not start that part of the scan.

**A pair of person accounts never appears either.** If your org stores people as person
accounts, merge two of them with Salesforce's own account merge. BarnCRM handles it as it
does a merge of two contacts: the kept person joins every household the other one belonged
to, each household keeps its primary member, an emptied household is kept, and the kept
person's totals are recalculated straight away.

**A Nonprofit Cloud household never appears.** In an org that also uses Salesforce Nonprofit
Cloud households, a household that is one of those is not suggested and cannot be merged here
or with **Merge or Split**: merging deletes one of the two records, and its Nonprofit Cloud
household group would be deleted or moved with it. Combine those with Nonprofit Cloud's own
tools.

**A person account is never paired with a contact.** Salesforce cannot merge the two, so such
a pair is not suggested.

**Scan for duplicates is greyed out.** A scan is already running, perhaps one a colleague
started. Wait for it to finish and choose **Refresh**. Two scans at once would suggest the
same pairs twice, so a second one is refused.

**A household pair should not be merged with the Salesforce merge.** Always merge households
from this panel or with **Merge or Split** on the household's record page. That merge moves
the members, recalculates the totals and renames the household, and lets you choose what to
keep. If two households are merged with Salesforce's own account merge anyway, BarnCRM recounts
and renames the kept household, settles its primary member and keeps one primary address within
a minute or so, in the background, because Salesforce does not let anything change the records
while it is merging them. If a person was in both households, they are left with one membership in the kept household (the primary one, or else the earlier start), so they are counted once. It cannot ask which name or members to keep, which is why the
household record page does not offer that merge.

**A merge run by another app or a background job.** The tidy-up after a Salesforce merge (one
membership per person, the count and name, one primary address, no relationship with oneself,
the primary affiliation) also runs when the merge was made by a background job, an
integration or a deduplication app. When the merge itself runs in the background, BarnCRM
asks for the tidy-up once the merge is saved, so it can take a minute or two longer. That
tidy-up runs as Salesforce's Automated Process user, so it shows as **Last Modified By** on the
addresses, relationships and memberships it changed. Only if
Salesforce refuses that request (for example, the org has used its daily allowance of
events) does the **Error Log** get a Warning, under the context "Tidy-up after a merge",
naming the kept records and the reason. Open each record named and correct it by hand.

**A colleague cannot find the panel, or sees it without buttons.** The **Review** area of the
**Duplicate Matching** tab needs BarnCRM Admin or BarnCRM Duplicate Review, and the tab
appears a minute or so after either is given. Scanning, dismissing and merging from it need
the Manage BarnCRM Settings permission, which the BarnCRM Admin permission set grants, and
access to duplicate record sets, which the BarnCRM Duplicate Review permission set grants.
Duplicates are no longer in **Org Optimizer**.

**The panel says suggestions need access to duplicate record sets.** The person
viewing it does not have BarnCRM Duplicate Review, or has a license that cannot have it.
Give them the permission set in BarnCRM Settings, **Access**, under **Extra Permissions** (see
How to turn it on). A Salesforce Platform user cannot
be given it at all; ask a colleague with a Sales Cloud or Service Cloud license to review.

**The last-scan line is red.** Salesforce refused to check some batches of up to 50 records, for
example because a duplicate rule was switched off during the scan, or could not save some
suggestions. The details are in the **Error Log**, under the context "Duplicate scan". Fix the
cause and scan again: pairs already found are not suggested twice.

**After merging two people, an empty household is left.** That is on purpose. Records made
while the other person lived there (with Giving, their gifts) still name that household. Until you merge it, Health Check
lists it under **Households have nobody in them**. Merge it into the kept person's household
from this panel or with **Merge or Split** on the household's page.

**You dismissed a pair and now want it back.** Dismissals are records. On the panel, choose
**View** next to **Dismissed pairs**, pick the **All Duplicate Dismissals** list, find the pair
by its reason, and delete it. The next scan suggests that pair again. Anyone with BarnCRM
Admin can delete a dismissal, whoever made it: a dismissal is the organization's decision.
