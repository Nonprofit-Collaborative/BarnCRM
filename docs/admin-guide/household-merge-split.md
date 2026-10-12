# Merging and splitting households

**Feature:** C-09 Household merge and split
**Package:** Core
**Iteration:** v0.1

## What it does

Imports and busy weeks leave you with the same family twice, or with two people who no
longer share a household. Merge combines two households into one: everybody ends up in the
surviving household, and the giving history, letters, files, and notes from both come with
them. Split moves one or more people out of a household into a new one or into a household
you already have.

Both are buttons on the household record page. Neither one needs Salesforce Setup, a data
loader, or a consultant.

## How to turn it on

Merging and splitting work as soon as Core is installed. There is nothing to switch on.

Two things decide who can do it and what happens afterwards.

**Who can do it.** Anyone who can edit both households can merge or split them. There is no
separate permission to hand out: if a person is trusted to edit the two records, they are
trusted to combine them. A person with read only access sees the panel with a note saying
they cannot make changes. Data cleanup is work Maria and David both do, so it is not locked
behind the administrator permission.

**What happens to the household you merge into.** It stays, always. "Delete a household
when the last person leaves" is about a household somebody was the last to leave, not about
the one you chose to keep, so merging two households that both happen to have no members in
them leaves you with one empty household rather than with none.

**What happens to the empty household after a split.** If "Delete a household when the last
person leaves" is on (Open Impact Settings, Households), a household that a split empties is
deleted for you. If it is off, the empty household stays and you delete it yourself. The
setting is on when Core is installed.

**Where the button is.** Core ships the placement, not just the action: the **Merge or
split** action sits in the action bar of the packaged Account record page, on households
only, and the Open Impact app opens households on that page, on the desktop and on the
phone. So the button is there on a fresh install, with nothing to wire up in the Lightning
App Builder. If you do not see it, the two usual reasons are that you are looking at the
record outside the **Open Impact** app (another app can carry its own record page
assignment), or that somebody has since overridden the assignment in the Lightning App
Builder.

## A five-minute walkthrough

Maria does this from the sample data, after an import left her with the Garcia family twice.

### Merging two households

1. Open the **Open Impact** app and click the **Households** tab.
2. Open **The Garcia Family**. Note that Harper, Luis and Diego Garcia are its members.
   The sample data ships one Garcia household, so to follow the merge make a second one
   first: a household named Garcia with a member or two in it, standing in for the
   duplicate an import would have left.
3. Click **Merge or split households**, then stay on the **Merge** tab.
4. In the search box, type `Garcia`. Pick **Garcia Household**, the duplicate the import
   created. Two columns appear side by side: the household you started from on the left, the
   one you picked on the right.
5. Read the comparison. Where the two households disagree, you get a choice: the name, the
   "custom name" box, the formal and informal greetings, the primary contact, the
   anniversary, and each line of the billing address. In the flexible way of belonging the
   primary contact is not offered: the household you keep keeps its primary member, and the
   other household's primary member stays primary only when the one you keep has none.
   Where they agree, the value is simply shown. Under the comparison, the **Members after the merge** list shows everyone who will
   be in the household when you are done.
6. Choose the values you want to keep. Take the name **The Garcia Family**, the anniversary
   from the duplicate (the import brought it in and the original never had one), and the
   left-hand address.
7. Click **Merge**. A confirmation appears saying which household survives, which one goes
   away, and that a merge cannot be undone. Read it, then click **Merge households**.
8. You land on the surviving household. It lists all of the members from both households,
   the member count is right, and the name has been recalculated from the members unless you
   chose to keep a custom name. Every gift, letter, file, and note from the duplicate is now
   on this household.

### Splitting a member out

9. Still on the Garcia household, click **Merge or split households** again and choose the
   **Split** tab.
10. Tick **Diego Garcia** in the member list.
11. Leave **A new household** selected and click **Split**. Confirm.
12. You land on Diego's new household, named **The Garcia Family** because that is what
    its one member makes it. Go back to the household you split him out of: its member
    count is one lower. Both names were recalculated for you.

To move someone into a household you already have instead, choose **An existing household**
in step 11 and search for it by name.

That is the whole job: two families become one, one person becomes their own household, and
nobody typed a name.

## Common mistakes

**"I merged the wrong households. How do I undo it?"**
You cannot. A merge is permanent: the household you merged away is deleted and its records
are moved to the survivor. This is why the confirmation names both households and warns you.
Read that screen every time. If you are unsure, open both households in other tabs first and
compare them there.

**"Merge will not let me pick the other record."**
The search only offers households. Organizations, companies, foundations, and churches you
raise money from are not households, and merging one into a household would destroy the
distinction the whole product relies on. If two organizations are duplicates, merge them
with the standard Salesforce account merge instead. The message you see is "Both records
must be households. Choose a household, not an organization."

**"It says I cannot edit one of these households."**
Merging edits both records, so you need edit access on both. A split works the same way when
you send people to a household you already have: you need edit access on the household they
leave and on the one they join. If you have it on one only, ask
whoever manages access to give you edit on the other, or ask them to run the merge. The
message is "You need edit access to both households to merge them."

**"After the merge the household name is not what I chose."**
If you left the "custom name" box unchecked, the name is recalculated from the members after
the merge, which is usually what you want: the household now holds more people. To keep the
exact name you chose, tick the custom name option in the comparison. That tells Open Impact
to stop recalculating this household's name and greetings, and your wording stands.

**"I split someone out and the old household disappeared."**
The person you moved was the last one in it, and "Delete a household when the last person
leaves" is on. Turn that setting off in Open Impact Settings if you would rather keep empty
households and their giving history.

## Where the record of a merge lives

Salesforce records account merges itself. The surviving household's history shows the merge
and who did it, and the records that moved carry their own history, so a merge is auditable
without Open Impact writing a second log of its own. Open Impact does not add an Error Log
entry for a successful merge, only for one that fails.

## Field reference

For report builders only. Maria never needs this to use the feature.

| Where | Field label | Purpose |
|---|---|---|
| Household | Custom Name | When ticked, the name and greetings are never recalculated |
| Household | Member Count | Recalculated on both households after a merge or a split |
| Household | Primary Contact | One of the values a merge offers a choice about in the simple way of belonging (in the flexible way it follows the primary member), and cleared on a household a split moves that person out of |
