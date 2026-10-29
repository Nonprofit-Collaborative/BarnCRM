# Households

**Feature:** C-01 Household model
**Package:** Core
**Iteration:** v0.1

## What It Does

A household is the group of people you treat as one: one mailing, one letter, one shared
history. BarnCRM creates a household for every new person you add,
in either way of belonging to a household and whichever record your org stores people on,
keeps track of who belongs to it, and keeps the member count right when people join, move,
or leave.

You never have to create a household by hand, and you never have to remember to fix a
count after a change.

**Households BarnCRM creates are saved past your org's Account duplicate rules.** A household
is named from its members, so two Garcia families give two households that look alike without
being duplicates, and a blocking Account duplicate rule would otherwise refuse the household
and, with it, the save of the person you were adding. A rule set to report still reports them,
and BarnCRM's duplicate review lists them like any other account, so you can merge real
duplicates there. A household account saved directly, from the Accounts tab or a data loader,
is checked by your rules as usual.

## How to Turn It On

Households belong to the **Household Upkeep** feature. Turn it on in first-run setup, or later
with **Turn On** in its row on **General** in BarnCRM Settings. Everything you can change is on
the BarnCRM Settings page, so nobody needs to open Salesforce Setup.

**The Household record type and the Households tab.** BarnCRM installs one Account record
type, **Household**. Setup lists it on every install, because a package cannot leave out a
record type it ships, but BarnCRM never gives it to anyone, so nobody is ever offered it when
creating an account and your users' record type choices stay as they were. Households are
made only by BarnCRM: automatically for new people, with **New Household** on BarnCRM Home,
and by merge and split. Staff open and edit a household like any account. Do not add the
Household record type to profiles or permission sets yourself: anyone who has it, and whose
profile has no default Account record type, gets Household for every account they create.

The **Households** tab is hidden until you turn Household Upkeep on. Turning it on shows the
tab to everyone with a BarnCRM role (Admin, Staff or Read Only), through the permission set
**BarnCRM Households**, within a few minutes. The confirmation says so, and reminds staff to
create households with **New Household** on BarnCRM Home, not the standard **New** button.
The permission set shows the tab and nothing else, and gives no record type. BarnCRM keeps it
in step like the tool tab sets, so do not assign it by hand: the nightly run removes it from
anyone without a BarnCRM role, who should be given a role on the Access page instead. Upgrading
an org that already ran BarnCRM removes the Household record type from the three role
permission sets (Salesforce drops a record type a permission set no longer names); accounts
that are households stay households.

BarnCRM does not add an Organization record type. Organizations are the accounts of the
record type you choose in **Record type for organizations** on **General** (see
[BarnCRM Settings](barncrm-settings.md)), so your own business record type keeps working.

1. Open the **BarnCRM Admin** app and click the **BarnCRM Settings** tab.
2. Click **People and Households** in the left navigation.
3. Check the four settings and change any that do not match how you work. The first two are
   in the **People** box, the other two in the **Households** box.

| Setting | What it does | Ships as |
|---|---|---|
| How people belong to a household | The simple way (one household per person) or the flexible way (a person can belong to more than one household, and you keep the history of who belonged when) | The simple way: one household per person. Until somebody chooses, the console shows **One household per person (simple)** as selected, and saving other settings leaves it that way |
| Create a household automatically | When you save a new person with no household, one is created for them. This works the same way in both ways of belonging, and for people stored as contacts and for people stored as accounts | On |
| Delete a household once it is empty | Keeps your list of households clean. A household is left alone when anything outside BarnCRM still depends on its account record, so this never removes a household another product built. A household that still has gifts or other records credited to it, such as volunteer hours, is kept too, so they never lose their household | Off, switch it on if you want it |
| Keep the households of deleted people | When you delete the last person in a household, the household stays at first, so you can still restore the people from the Recycle Bin. Once nobody from it is left in the Recycle Bin, a nightly tidy-up moves the household to the Recycle Bin too, unless anything else is still linked to it. Switch this on to keep those households instead | Off, so the tidy-up runs |

4. Click **Save**. The change applies to the next record anyone saves.

Choose the flexible way if you need one person in two households: a child of divorced
parents, or a student with a family address and a campus address. The rest of the product
behaves the same either way, so it is safe to start simple. Change your mind early, though:
each way keeps its own record of who belongs where, and the other way cannot see it, so
once people are in households BarnCRM refuses the switch and tells you how many people
it would affect. Moving them across is a migration, which BarnCRM does not do yet.

## A Five-Minute Walkthrough

Maria does this from the sample data.

1. Open the **BarnCRM** app and click the **Contacts** tab.
2. Click **New** and enter the first name `Maria` and the last name `Garcia`. Leave the
   household blank. Click **Save**.
3. Look at the household field on the new person. It is filled in, and the household is
   called **The Garcia Family**. Maria did not create it.
4. Click through to the household. The **Members** panel lists Maria, and the member count
   reads 1.
5. On the Members panel, click **Add Member** and enter the first name `Wei` and the last
   name `Lee`. Click **Save**.
6. Refresh the household. The name now reads **Garcia and Lee Household** and the member
   count reads 2.
7. Open Wei's record, check **Deceased**, and save. Return to the household: the greetings
   no longer mention Wei.
8. Back on the Members panel, use **Move to Another Household** on Maria and move her to
   any other household. Return to the first household: it is still there, with nobody in
   it and a member count of 0, because "delete a household when the last person leaves"
   ships off. It keeps the name and greetings it had last, so a report still shows which
   family it was. Switch that setting on in BarnCRM Settings if you would rather it were
   removed, and the next household left empty is.

That is the whole lifecycle: created for you, named for you, counted for you, and tidied
up for you if you ask.

To start from the household instead of the person, click **New Household** on the Hub
home. BarnCRM creates the household straight away, with a placeholder name that the naming
automation replaces once you add a member, and opens it. There is no record type to choose
and no name to invent.

The walkthrough reads the same in the flexible way of belonging, with one difference at
step 3: the household is not shown in the household field on the person, because in that
mode membership is a record of its own. Open the household from the **Households** tab, or
from the Household panel on the person, and everything from step 4 on is identical. (On a
person account the panel is there once you add it to the page: see "The Household panel on
a person" in [Household members](household-members.md).)

One thing the tidy-up will not do: it never deletes a household that something outside
BarnCRM still points at, even when the setting is on and nobody is left in it. It
leaves that household alone and writes an Info entry in the Error Log naming it, so you
can look at it and decide for yourself.

## If Your Org Stores People as Accounts

Some orgs store each person as an account (Salesforce calls this Person Accounts) rather
than as a contact. Households work there too, with one difference:
choose the flexible way of belonging to a household. It is the only mode that can hold a
person who is stored as an account, and BarnCRM selects it for you when it is installed
and notices your org is shaped that way. It does that only when nobody has chosen a way of
belonging yet: if you chose the simple way on purpose, because your org has Person Accounts
switched on but stores everyone as a contact, an install or upgrade leaves your choice
alone, and Health Check warns you if people stored as accounts appear later.

In the flexible way, a new person stored as an account gets a household of their own when
they are saved, as a contact does. People stored as accounts who were added while Household
Upkeep was off are caught up when it is turned on, along with contacts: see "First-run setup" in
the BarnCRM Settings guide.

In the flexible way a contact's account can be an employer, so it is not the household by
itself. When you save a new contact whose account is a household, though, BarnCRM joins them
to that household with a membership record, so they are counted and named there and are not
given a second household. A contact saved against an organization is not joined to it.

Automatic creation is the same setting and the same behavior as anywhere else. When "create
a household automatically" is on, saving a new person creates their household and the
membership record that joins them to it, whether that person is a contact or an account.
There used to be a second setting here, "create households for people stored as accounts",
and it has been removed: it shipped off, so an org that took the recommended setup got no
households at all and was told nothing about it. One setting now answers the question for
everybody.

If you are one of the orgs that groups people another way and does not want a household
appearing for each person, turn "create a household automatically" off. Health Check will
tell you the state you are in, so it is a choice rather than a surprise.

Everything else reads the same: the same member counts, the same names and greetings, and
the same Members panel. A household is still its own record, never a person.

## Common Mistakes

**"There is no Households tab."**
Household Upkeep is off. Turn it on in **General**; the tab reaches everyone with a BarnCRM
role within a few minutes. Someone without a BarnCRM role does not get it: give them a role on
the Access page.

**"Nobody can choose Household when creating an account."**
That is by design. Create households with **New Household** on BarnCRM Home, or add a person
and let BarnCRM make their household. An account can't be changed to Household either.

**"Every new account someone creates turns into a household."**
Someone gave that person the Household record type in a profile or permission set, and their
profile has no default Account record type. Remove the Household record type from them.

**"I added a person and no household appeared."**
Either "create a household automatically" is off, or the person already belongs to a
household: you filled the household in yourself when you created them, or a membership
record already joins them to one. Turn the setting back on in BarnCRM Settings, then open
the person and pick or create a household. Health Check reports the setting being off as a
red finding, with a button that turns it on.

**"I cannot change how people belong to a household."**
The two ways of belonging keep separate records of who is in which household, and each is
invisible to the other. Switching with people already in households would make their
households read as empty, or leave the people belonging nowhere, so BarnCRM refuses
and tells you how many people it would affect. Moving them across is a migration, which
BarnCRM does not do yet. If the setting was changed some other way and Health Check
reports household members it cannot see, switch back to the way of belonging the records
were made in.

**"I deleted the last person and the household is still there."**
Either "Delete a household once it is empty" is off, or BarnCRM deliberately
left that one alone.

Deleting people never deletes their household straight away; moving them out still tidies it away.
Deleting the household too would empty those people out of the Recycle Bin, and you could not
restore them. If you meant to remove both, delete the household by hand.

Unless "Keep the households of deleted people" is on, a nightly tidy-up comes back for the
household once nobody who belonged to it is left in the Recycle Bin (the Recycle Bin empties
itself after 15 days, or sooner if someone empties it). It then moves the household to the
Recycle Bin, where you can still restore it. The household's own addresses go to the Recycle
Bin with it, and the import that created it keeps its record. It leaves the household alone
when anything else is still linked to it: gifts, pledges, relationships, tasks, files, the
past membership of someone who moved out (or was erased), or any other record, whichever
product made it. Those households stay on the "households with nobody in them" lists in
Health Check and Org Optimizer's Data Quality for you to review. Households emptied before this
tidy-up was added, and households a merge or a move emptied, are never part of it. Schedule
it with Health Check's **Nightly jobs are not scheduled** fix.

If the setting is off, that is a reasonable choice if you want to keep an empty household
and its giving history. Delete the household by hand, and turn the setting on if you want
it done for you next time.

If the setting is on, check what is credited to the household first. A household that still
has gifts or other records credited to it, such as volunteer hours, is never deleted, even
when nobody belongs to it any more (with Giving, its gifts and pledges; with Volunteers, its
volunteer hours): a gift stays with the household it was given from, and deleting the
household would leave those records with no household at all. This is the ordinary outcome
when someone with a giving or volunteering history moves out on their own, so it is not
written to the Error Log. The household keeps the name and greetings it had last, so reports
still show which family it was. Leave the household in place if you want its history kept
together; merge it into another household if you want that history combined with theirs.

Otherwise, look in the Error Log. BarnCRM never deletes a household that
something outside BarnCRM still points at, because deleting it would delete those
records too, and it writes an Info entry naming each household it left in place for that
reason. In an org that also runs Salesforce Nonprofit Cloud, this happens most often because a
household is a second record attached to the same account and its members are held
somewhere BarnCRM cannot count them: the household looks empty here and is not empty
there. Open the household, check what else is using it, and delete it by hand if you are
sure.

**"The member count looks wrong."**
The count includes current members only. In the flexible membership mode, a person whose
membership has an end date of today or earlier has left the household and is not counted.
The Members panel lists current members only and shows no dates, so somebody who has left
is simply absent from it.

**"The primary contact went blank when I moved someone out."**
That is deliberate. The primary contact has to be somebody who is still in the household,
so when that person leaves, BarnCRM clears the field rather than leaving a name that no
longer belongs there. It does not choose a replacement for you: click **Make Primary**
on the right person in the household's **Members** panel. In the flexible way of
belonging the field always follows the member marked primary, so that panel is the only
place to change it.

**"I moved someone and their history stayed behind."**
That is deliberate. Moving a person moves the person, not the history of the household
they left (with Giving, that includes the household's gifts). Use merge on the household record page when you want to combine two
households and their history. A household left with nobody in it but with gifts or other
records credited to it, such as volunteer hours, is kept, even when "Delete a household once
it is empty" is on, so that history always has a household to belong to.

## Field Reference

For report builders only. Maria never needs this to use the feature.

| Where | Field label | Purpose |
|---|---|---|
| Household | Member Count | Current members of this household |
| Household | Primary Contact | The person named when only one person can be. Cleared when that person leaves the household. In the flexible way of belonging it follows the member marked primary, and a person account appears as its person contact |
| Household | Anniversary | A household date you steward, most often a wedding anniversary |
| Household | Emptied By Deletion | The day the last person in this household was deleted. Cleared when someone joins again. Only households with this date are considered by the nightly tidy-up. Clear it to keep one household |
| Person | Household Role | Head, Spouse or Partner, Child, or Other |
| Household Member | Start Date and End Date | When the person joined and left (flexible mode only) |
