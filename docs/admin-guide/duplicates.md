# Duplicates

## What it does

Finds people and households that are in your database twice, and helps you deal with them one
pair at a time. Salesforce does the finding, with the duplicate rules every org starts with:
it warns the person typing that somebody similar already exists. What Salesforce does not do
in most editions is look through the records you already have, so a spreadsheet imported last
year is never checked against itself. Open Impact adds that scan, lists every pair on one page,
and puts the household merge one click away.

Nothing is ever merged or deleted for you. Every merge is a pair you looked at and confirmed.

## How to turn it on

There is nothing to install. Salesforce switches on its standard duplicate rules for people
and accounts in every new org, and Open Impact uses them. There is one Setup step, because of a
Salesforce licensing rule:

**Who can review duplicates.** Salesforce keeps possible duplicates in records called duplicate
record sets, and gives access to them only to users with a **Sales Cloud or Service Cloud
license**. No other license can have it, Salesforce Platform included. So Open Impact puts that
access in its own permission set, **Open Impact Duplicate Review**, which is in no role. In Setup,
open **Users**, choose each person who will review duplicates, and under **Permission Set
Assignments** add **Open Impact Duplicate Review**. Salesforce refuses the assignment for a user
without one of those licenses. If nobody in your org has one, duplicate rules still warn people
as they type, but nobody can review or merge suggestions: not on this panel, and not on the
**Potential Duplicates** card on a contact's page, which reads the same records and shows a
Platform user nothing usable.

1. Open the **Open Impact** app and choose **Open Impact Settings**.
2. In the left navigation choose **Households**, and scroll to **Duplicates**.
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

1. Open **Open Impact Settings**, choose **Households**, and scroll to **Duplicates**.
2. Choose **Scan for duplicates**. You see "Scan started. It runs in the background, and
   suggestions appear here as they are found."
3. Wait a minute and refresh the page. Under **Possible duplicates** you see the pair you made,
   each person with their email address.
4. Choose the person's name to open their record. On the right of the page the **Potential
   Duplicates** card names the other record. Choose **View Duplicates**, then **Compare and
   merge**, pick the values to keep, and confirm. This is Salesforce's own merge, and it keeps
   the gifts, activities and files of both. Open Impact then adds the kept person to any
   household the other one belonged to, and recalculates their giving totals straight away.
   A household the other person leaves empty is kept, not deleted, because gifts are credited
   to it: merge it into the kept person's household with **Merge households** (step 6).
5. Back on the Duplicates panel, refresh. The pair is gone.
6. If the scan found two households, choose **Merge households** on the pair. You see the two
   side by side, the fields where they disagree, and which one is kept. Choose the household to
   keep and choose **Merge these two**. You see "The two households are now one."
7. For a pair that is not the same person, for example twin sisters at one address, choose
   **Not a duplicate**, type a short reason, and confirm. You see "Noted. This pair will not be
   suggested again." Scan again and check that the pair does not come back.

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
organizations with Salesforce's own tools.

**A pair of person accounts never appears either.** If your org stores people as person
accounts, merge two of them with Salesforce's own account merge. Open Impact handles it as it
does a merge of two contacts: the kept person joins every household the other one belonged
to, each household keeps its primary member, an emptied household is kept, and the kept
person's totals are recalculated straight away.

**A household pair should not be merged with the Salesforce merge.** Always merge households
from this panel or with **Merge or split** on the household's record page. That merge moves
the members, recalculates the totals and renames the household; Salesforce's own account merge
does none of that, which is why the household record page does not offer it.

**A colleague sees the panel but the buttons are missing.** Scanning, dismissing and merging
from this panel need the Manage Open Impact Settings permission, which the Open Impact Admin
permission set grants, and access to duplicate record sets, which the Open Impact Duplicate Review
permission set grants.

**The panel says suggestions need access to duplicate record sets.** The person
viewing it does not have Open Impact Duplicate Review, or has a license that cannot have it.
Assign the permission set in Setup (see How to turn it on). A Salesforce Platform user cannot
be given it at all; ask a colleague with a Sales Cloud or Service Cloud license to review.

**The last-scan line is red.** Salesforce refused to check some batches of up to 50 records, for
example because a duplicate rule was switched off during the scan, or could not save some
suggestions. The details are in the **Error Log**, under the context "Duplicate scan". Fix the
cause and scan again: pairs already found are not suggested twice.

**After merging two people, an empty household is left.** That is on purpose. Gifts given
while the other person lived there still name that household. Until you merge it, Health Check
lists it under **Households have nobody in them**. Merge it into the kept person's household
from this panel or with **Merge or split** on the household's page.

**You dismissed a pair and now want it back.** Dismissals are records. On the panel, choose
**View** next to **Dismissed pairs**, pick the **All Duplicate Dismissals** list, find the pair
by its reason, and delete it. The next scan suggests that pair again.
