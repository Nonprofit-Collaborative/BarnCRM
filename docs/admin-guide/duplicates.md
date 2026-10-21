# Duplicates

## What it does

Finds people and households that are in your database twice, and helps you deal with them one
pair at a time. Salesforce does the finding, with the duplicate rules every org starts with:
it warns the person typing that somebody similar already exists. What Salesforce does not do
in most editions is look through the records you already have, so a spreadsheet imported last
year is never checked against itself. BarnCRM adds that scan, lists every pair on one page,
and puts the household merge one click away.

Nothing is ever merged or deleted for you. Every merge is a pair you looked at and confirmed.

## How to turn it on

There is nothing to install, but on a new install the **Duplicate Review** feature is off
until you turn it on: choose **Turn on** in the **Duplicate Review** row in **BarnCRM
Settings**, **General** (or leave it ticked in first-run setup); see
[BarnCRM Settings](barncrm-settings.md). Salesforce switches on its standard duplicate rules
for people and accounts in every new org, and BarnCRM uses them. There is one permission
step, because of a Salesforce licensing rule:

**Who can review duplicates.** Salesforce keeps possible duplicates in records called duplicate
record sets, and gives access to them only to users with a **Sales Cloud or Service Cloud
license**. No other license can have it, Salesforce Platform included. So BarnCRM puts that
access in its own permission set, **BarnCRM Duplicate Review**, which is in no role. In BarnCRM
Settings, open **Access** and, under **Extra permissions**, give **BarnCRM Duplicate Review** to
each person who will review duplicates. Salesforce refuses the assignment for a user
without one of those licenses. If nobody in your org has one, duplicate rules still warn people
as they type, but nobody can review or merge suggestions: not on this panel, and not on the
**Potential Duplicates** card on a contact's page, which reads the same records and shows a
Platform user nothing usable.

1. Open the **BarnCRM** app and choose the **Org Optimizer** tab.
2. Choose **Duplicates**. (In **BarnCRM Settings**, **Households**, the **Duplicates** row's
   **Open this page** button brings you here too.)
3. Under **Duplicate rules** each rule for people and accounts is listed with On or Off. At
   least one should say On. If none does, see Common mistakes below.
4. Choose **Scan for duplicates**. The scan looks through the people and households you
   already have. It runs in the background and can take a while in a large database.
5. When it finishes, the line under the button says what the last scan did, for example
   "Duplicate scan of Contact, Account finished: 3 new possible duplicates recorded." If part of
   the database could not be checked, the line is red and says how many batches of up to 50
   records could not be checked; see Common mistakes below.

Run the scan again after a large import: Salesforce checks a record against the others when
it is saved, but an import that saved past a warning leaves the pair for the scan to find.

## A five-minute walkthrough

Start with the sample data loaded (see [sample-data.md](sample-data.md)). Create one duplicate
on purpose: open any sample person, note their email address, and create a new contact with
the same first name, last name and email. Salesforce warns you that a similar record exists;
choose to save anyway.

1. Open **Org Optimizer** and choose **Duplicates**.
2. Choose **Scan for duplicates**. You see "Scan started. It runs in the background, and
   suggestions appear here as they are found."
3. Wait a minute and refresh the page. Under **Possible duplicates** you see the pair you made,
   each person with their email address.
4. Choose the person's name to open their record. On the right of the page the **Potential
   Duplicates** card names the other record. Choose **View Duplicates**, then **Compare and
   merge**, pick the values to keep, and confirm. This is Salesforce's own merge, and it keeps
   the activities and files of both (and, with Giving, their gifts). BarnCRM then adds the
   kept person to any household the other one belonged to, and recalculates their totals
   straight away. A household the other person leaves empty is kept, not deleted, because
   records can still point at it: merge it into the kept person's household with **Merge households** (step 6).
   Within a minute or so BarnCRM also tidies the kept person in the background: one default
   address stays (see [Addresses](addresses.md)), a relationship the two records had with each
   other is removed, so is a second copy of a relationship both had with the same person, and
   their primary affiliation is chosen again.
5. Back on the Duplicates panel, refresh. The pair is gone.
6. If the scan found two households, choose **Merge households** on the pair. You see the two
   side by side, the fields where they disagree, and which one is kept. Choose the household to
   keep and choose **Merge these two**. You see "The two households are now one."
7. For a pair that is not the same person, for example twin sisters at one address, choose
   **Not a duplicate**, type a short reason, and confirm. You see "Noted. This pair will not be
   suggested again." Scan again and check that the pair does not come back. It stays off the
   panel even when a duplicate rule reports the pair again as someone saves one of the two.
   A suggestion that names three or more records (one a duplicate rule wrote as someone saved)
   is dismissed as a whole: every pair in it is noted. If two of them are in fact the same
   person, merge those first, then dismiss the rest.

## Common mistakes

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
or with **Merge or split**: merging deletes one of the two records, and its Nonprofit Cloud
household group would be deleted or moved with it. Combine those with Nonprofit Cloud's own
tools.

**A person account is never paired with a contact.** Salesforce cannot merge the two, so such
a pair is not suggested.

**Scan for duplicates is greyed out.** A scan is already running, perhaps one a colleague
started. Wait for it to finish and choose **Refresh**. Two scans at once would suggest the
same pairs twice, so a second one is refused.

**A household pair should not be merged with the Salesforce merge.** Always merge households
from this panel or with **Merge or split** on the household's record page. That merge moves
the members, recalculates the totals and renames the household, and lets you choose what to
keep. If two households are merged with Salesforce's own account merge anyway, BarnCRM recounts
and renames the kept household, settles its primary member and keeps one default address within
a minute or so, in the background, because Salesforce does not let anything change the records
while it is merging them. If a person was in both households, they are left with one membership in the kept household (the primary one, or else the earlier start), so they are counted once. It cannot ask which name or members to keep, which is why the
household record page does not offer that merge.

**A merge run by another app or a background job.** The tidy-up after a Salesforce merge (one
membership per person, the count and name, one default address, no relationship with oneself,
the primary affiliation) also runs when the merge was made by a background job, an
integration or a deduplication app. When the merge itself runs in the background, BarnCRM
asks for the tidy-up once the merge is saved, so it can take a minute or two longer. That
tidy-up runs as Salesforce's Automated Process user, so it shows as **Last Modified By** on the
addresses, relationships and memberships it changed. Only if
Salesforce refuses that request (for example, the org has used its daily allowance of
events) does the **Error Log** get a Warning, under the context "Tidy-up after a merge",
naming the kept records and the reason. Open each record named and correct it by hand.

**A colleague cannot find the panel, or sees it without buttons.** The Duplicates section of
Org Optimizer, and scanning, dismissing and merging from it, need the Manage BarnCRM Settings
permission, which the BarnCRM Admin permission set grants, and access to duplicate record sets,
which the BarnCRM Duplicate Review permission set grants.

**The panel says suggestions need access to duplicate record sets.** The person
viewing it does not have BarnCRM Duplicate Review, or has a license that cannot have it.
Give them the permission set in BarnCRM Settings, **Access**, under **Extra permissions** (see
How to turn it on). A Salesforce Platform user cannot
be given it at all; ask a colleague with a Sales Cloud or Service Cloud license to review.

**The last-scan line is red.** Salesforce refused to check some batches of up to 50 records, for
example because a duplicate rule was switched off during the scan, or could not save some
suggestions. The details are in the **Error Log**, under the context "Duplicate scan". Fix the
cause and scan again: pairs already found are not suggested twice.

**After merging two people, an empty household is left.** That is on purpose. Records made
while the other person lived there (with Giving, their gifts) still name that household. Until you merge it, Health Check
lists it under **Households have nobody in them**. Merge it into the kept person's household
from this panel or with **Merge or split** on the household's page.

**You dismissed a pair and now want it back.** Dismissals are records. On the panel, choose
**View** next to **Dismissed pairs**, pick the **All Duplicate Dismissals** list, find the pair
by its reason, and delete it. The next scan suggests that pair again. Anyone with BarnCRM
Admin can delete a dismissal, whoever made it: a dismissal is the organization's decision.
