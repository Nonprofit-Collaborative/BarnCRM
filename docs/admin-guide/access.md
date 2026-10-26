# Access: give a colleague access by name and role

## What it does

Access lets you give a colleague what they need to do their job by picking their name and
choosing a role, for example Team Member or Read Only. You never have to learn what a
permission set is, and you never have to open Salesforce Setup to change someone's role. The
page also shows you, at a glance, who currently holds each role, so you can answer "who can
change our settings?" in a few seconds.

Roles ship with BarnCRM and are kept up to date for you.

A module ships its own permission sets, and a Core role cannot include them. They reach
people in one of two ways:

- **Volunteers and Rollup Builder follow the roles for you.** Their sets are given
  automatically to everyone holding the matching role (for example the Coordinator role gets
  **Volunteers Coordinator**), at the latest overnight.
- **Giving and Mirror sets are chosen per person, on this page.** Turning a module on in the
  [Module Manager](module-manager.md) gives its admin set (for Giving, **Giving Admin**) only to
  you, the person who turned it on. Everyone else gets **Giving Admin**, **Giving Staff**,
  **Giving Read Only**, **Campaign Sync**, **Opportunity Mirror**, **Accounting Export** and
  the rest under "Extra permissions" below, beside their role. The Fundraising Staff role
  already includes Giving Staff.

You never need Setup for either. If you would rather have a module set given automatically to
every new user, a Salesforce user access policy can do it: see
[Automatic access](automatic-access.md).

BarnCRM Core ships four roles. The Fundraising Staff role comes with the Giving module,
so it is listed only where Giving is installed, which makes five:

| Role | Who it is for | What it gives |
|---|---|---|
| BarnCRM Admin (its card and the role list say **BarnCRM Admin Group**, its label in Salesforce) | The person who configures the app, usually you | Everything, including BarnCRM Settings |
| Fundraising Staff (with Giving) | Development and fundraising staff | Day to day work with people, households, and giving, including the Giving Staff permission set |
| Team Member | Staff, members, or volunteers who do the day to day work | Day to day work with people, households, and organizations, plus program and service records when the Programs module is on |
| Coordinator | Whoever schedules people and tracks their time | Day to day work with people, households, and organizations, plus volunteer shifts and hours when the Volunteers module is on |
| Read Only | Board members, auditors, and anyone who should look but not change | Read access, no editing |

The role names fit any organization, nonprofit or not. In Setup, Team Member and Coordinator
keep their original API names, `Program_Staff` and `Volunteer_Coordinator`, so that upgrades
keep working; you only need those names for an
[automatic access](automatic-access.md) policy.

Of the roles, only BarnCRM Admin gives Delete on accounts and contacts (a person's Salesforce
profile may give it too). The other roles leave it out on purpose, and they do not need it for
merging households: anyone who can edit both households can merge
them with **Merge or split**, with no Delete permission (see
[Household merge and split](household-merge-split.md)). The roles do give edit on a contact's
**Account Name** (the household), so staff can move people between households, and move members
when they merge households, even on the Minimum Access profile. Merging two people uses Salesforce's
own **Compare and merge**, which Salesforce allows only to people who can delete them, so
staff ask an admin for that.

## Who can read a donor's receipts and tax statements (with Giving)

This section applies only when the Giving module is installed. Nobody sees a receipt PDF unless they hold one of the Giving module's permission sets. This is
worth stating plainly, because a file in Salesforce is reached through the record it is attached
to, not through the record it is about.

| Person | What they hold | Can they open a receipt PDF |
|---|---|---|
| Maria, who configures BarnCRM | BarnCRM Admin, plus Giving Admin | Yes |
| David, who enters the gifts | Fundraising Staff, which includes Giving Staff | Yes |
| Tom, on the board | Read Only, plus Giving Read Only | Yes, read only |
| Priya, who coordinates volunteers | Coordinator, and no Giving set | No |
| Sam, in programs | Team Member, and no Giving set | No |

Priya and Sam can open the donor's household and the donor's contact record, because that is
their job. What they cannot open is the receipt or the year-end statement, because a receipt PDF
is attached to the **Receipt** record and, for a single gift receipt, to the **Gift**, and both
of those need a Giving permission set. It is deliberately not attached to the household or the
contact: attaching it there would have handed every donor's tax history, and your organization's
tax identification number, to everyone who can read a contact.

So to find a donor's receipt, open the donor, then the **Receipts** related list, then the receipt,
then the file on it. If somebody says they cannot see receipts on a donor's record, that is this,
and the fix is a Giving permission set, which you give them under "Extra permissions" below.

Nobody can edit or delete a receipt PDF, whatever they hold. See
[Receipts and year-end statements](receipts.md).

## How to turn it on

There is nothing to turn on. Access is part of BarnCRM Core and appears in BarnCRM
Settings as soon as the package is installed.

The person who installs BarnCRM is given the BarnCRM Admin role automatically, at
install and again at every upgrade, so there is always at least one person who can use this
page. If that person was you, you can start straight away.

Three things control who can use the page:

1. You need the Manage BarnCRM Settings permission, which comes with the BarnCRM Admin
   role. Anyone without it sees the page in read-only mode with a notice explaining why.
2. To give or remove a role or an extra permission you also need Salesforce's **Assign
   Permission Sets** (or **Manage Users**) permission. A system administrator has it already. A BarnCRM Admin who is not a system
   administrator gets it from the optional **BarnCRM Access Manager** permission set: in
   Setup, open **Users**, choose the person, and under **Permission Set Assignments** add
   **BarnCRM Access Manager**. Assign Permission Sets is a Salesforce-wide permission: whoever
   holds it can also assign any permission set in Setup, not only the BarnCRM roles, so give
   it only to people you trust with that. It is in no role because only a full Salesforce license can
   hold it; a user with a **Salesforce Platform** license cannot be given it, so in that case
   a colleague with a Salesforce license gives the roles. Everything else in BarnCRM Settings
   works on a Platform license. The same permission lets the
   [Module Manager](module-manager.md) give you a module's admin set when you turn it on.
   Without it, the page shows who holds each role and extra permission, the **Give access**
   button is disabled, the extra permission picker and the **Remove** buttons are hidden, and a
   notice says why: "You can see who has each role and extra permission but not change
   them.", followed by where the permission comes from.
3. The person you are giving a role to must already be a Salesforce user with a license.
   Creating users is one of the few things Salesforce does not let an app do for you, so
   that step happens in Setup. See "What still needs Setup" below.

Giving the extra permissions (see "Extra permissions" below) needs the same two
permissions as giving a role.

## A five-minute walkthrough

Maria has just hired David to run a program. His Salesforce user already exists.
Here is how she gives him access, checks it, and takes it away again.

1. Open the BarnCRM app and click the **BarnCRM Settings** tab.
2. In the left navigation, choose **Access**. You see a card for each role (five with Giving,
   four without), each with a short description and the people who currently hold that role. On a fresh install only your
   own name appears, on the **BarnCRM Admin Group** card.
3. In the **Find a person** box, type `David`. Matching active users appear as you type,
   each with their name and email address so you can tell two Davids apart.
4. Choose **David Okafor**.
5. Choose the role **Team Member** and click **Give access**. A confirmation asks you
   to confirm the person and the role. Click **Give access** again.
6. A message says "David Okafor now has the Team Member role." David's name appears
   on the Team Member card, and the number in brackets beside the role name goes up
   by one.
7. David can now sign in and see households and contacts. He does not see BarnCRM
   Settings, because that belongs to the BarnCRM Admin role. If your org has Giving, he
   does not see gifts yet either: for that he also needs **Giving Staff**, which you give him
   on this page under "Extra permissions" below (or give him the Fundraising Staff role,
   which includes it).
8. To take the role away, find David's name on the Team Member card and click
   **Remove**. Confirm, and a message says "David Okafor no longer has the Team Member
   role." His name disappears from the card.

A person can hold more than one role. Giving David the Coordinator role as well
does not remove Team Member, and removing one role leaves the other in place. Giving someone a
role they already have changes nothing and reports no error.

## Extra permissions

A few BarnCRM features are in no role on purpose, because most people should not have them,
and a module's own permission sets cannot be in a Core role. You give them to a person on this
page too, alongside their role, under **Extra permissions**. You never need Setup for them.

Core's six are always listed:

| Extra permission | What it lets the person do |
|---|---|
| BarnCRM Find and Export | Build, run, save and export Find queries and use Data Hygiene, seeing only the records the person can already see. BarnCRM Admin already includes it. |
| BarnCRM Bulk Update | Set, clear or copy fields on many records at once from a Find query, with undo. Give it together with Find and Export. |
| BarnCRM Bulk Delete | Delete many records at once from a Find query, with undo from the Recycle Bin. Give it together with Find and Export. Marked with a warning. |
| BarnCRM Erase People | Erase a person on their request (the right to be forgotten), which cannot be undone. Marked with a warning. |
| BarnCRM Duplicate Review | Review suggested duplicate people and households, including reading the **Duplicates** list on Org Optimizer (scanning, dismissing and merging there stay with BarnCRM Admin). Works only for people with a Sales Cloud or Service Cloud license. |
| BarnCRM Metadata Admin | Save changes on the Custom metadata page of BarnCRM Settings, which changes the org's configuration. For people who already administer the org. |

A module's sets are listed after them, only where that module is installed:

| Extra permission | Module | What it lets the person do |
|---|---|---|
| Giving Admin | Giving | Configure giving and fix mistakes: funds, appeals, gifts, refunds and write-offs, including deleting a record entered by accident. |
| Giving Staff | Giving | Enter gifts, record refunds, and set up funds and appeals, without deleting anything. Run reports and view dashboards. The Fundraising Staff role already includes it. |
| Giving Read Only | Giving | See gifts, funds, appeals and receipts without changing them. Run reports and view dashboards. |
| Campaign Sync | Mirror | Edit an appeal's Campaign ID and open the Campaign sync page. Creating Campaigns also needs Campaign access and the Marketing User box on the person's user. |
| Opportunity Mirror | Mirror | Edit a gift's Opportunity ID and open the Opportunity mirror page. Creating Opportunities also needs Opportunity access. |
| Accounting Export | Mirror | Download gifts as a CSV file for your accounting system and mark them posted. Give it together with a Giving permission set that reads gifts. |
| Inbound Gift API | Mirror | For the integration user only: record gifts another system sends through the Inbound Gift API. It needs nothing else from BarnCRM. |
| Record Inbound Gift Action | Mirror | Run the Record Inbound Gift action from a flow or an AI assistant. Give it together with Giving Staff. |

The Volunteers and Rollup Builder sets are not listed, because they follow the roles
automatically (see the top of this page): removing one here would only be undone overnight.

These are the only permissions this section gives. It never lists or assigns any other
permission set in your org, including one you created yourself with the same name as one of
these.

To give one:

1. In the **Find a person** box, find and choose the person, as for a role.
2. In **Extra permission**, choose the permission. Its sentence from the table above appears
   under the picker. For Bulk Delete and Erase People a warning appears as well: "This
   permission lets the person remove data. Give it only to someone you trust to do that."
3. Click **Give permission**, and confirm. The confirmation repeats the warning. A message says,
   for example, "Priya Nair now has the BarnCRM Erase People permission."

Each extra permission has its own card below the roles, listing who has it, with a **Remove**
button beside each name. Removing it leaves the person's roles in place.

A card lists only people given the permission directly. Someone who has it through a role (every
BarnCRM Admin has Find and Export) is not listed, and removing it here could not take it away.

Who can give extra permissions: you need Manage BarnCRM Settings, as for roles, and also what
Salesforce itself asks for to assign a permission set in Setup: **Assign Permission Sets** (or
**Manage Users**). A system administrator has it; anyone else gets it from BarnCRM Access
Manager (see "How to turn it on"). Without it, the cards are shown with no buttons, under the
notice described there.

If Salesforce refuses one person, usually because their license does not allow what the
permission grants (Duplicate Review on a Salesforce Platform license, for example), the page says
so by name: "Priya Nair could not be given BarnCRM Duplicate Review. Their Salesforce license
may not allow what it grants. Salesforce said: ..." followed by Salesforce's own reason. The same
message is written to the Error Log. Removing works the same way: a person Salesforce will not
let you remove it from is named with the reason ("BarnCRM Bulk Update could not be removed from
Priya Nair. Salesforce said: ..."), and the others are still removed. Nothing is written to the
Error Log when it works.

## Tabs that follow a feature

Five tabs stay hidden for everyone until their feature is turned on in BarnCRM Settings,
General, Features: Data Manager, Import, Find, Bulk Update and Data Hygiene. So no role or
extra permission grants them any more. Each comes from its own permission set, **BarnCRM Tab:
(tab name)**, which BarnCRM gives automatically to the people who should see it once its
feature is on:

| Tab | Given to holders of |
|---|---|
| Data Manager | BarnCRM Admin, Find and Export, Bulk Update, Bulk Delete |
| Import | BarnCRM Admin |
| Find | BarnCRM Admin, Find and Export |
| Bulk Update | BarnCRM Admin, Bulk Update, Bulk Delete |
| Data Hygiene (Org Optimizer) | BarnCRM Admin, Find and Export, Duplicate Review |

This page keeps them in step when you give a role or extra permission. A role given in Setup or
by a user access policy is caught up overnight, and every upgrade catches everyone up, so an
upgraded org keeps exactly the tabs it had. The BarnCRM Tab sets are never listed on this
page and should not be assigned by hand. Nobody needs Assign Permission Sets for this: BarnCRM
does it itself, and the tab sets grant nothing but the tab.

## What still needs Setup

BarnCRM can give a person a role, but it cannot create the person or hand out a
Salesforce license. Only Salesforce Setup can do that, because licenses are billed and
managed by Salesforce rather than by an installed app.

So the order is always: create the user in Setup first, then give them a role here.

The **Create a user in Setup** link on the Access page opens the Users page in Setup in a
new tab. The address it opens is:

`/lightning/setup/ManageUsers/home`

Create the user with a Salesforce Platform or Salesforce license, save, then come back to
Access and search for their name.

If you add people often, you can skip the second step: a Salesforce user access policy can
give every new user with your staff profile a BarnCRM role the moment the user is created.
The **Set up automatic access** link at the bottom of the Access page opens
[Automatic access](automatic-access.md), which has the exact policy to create in Setup.

## Common mistakes

**You cannot find the person in the search box.** The search only shows active users. If
you just created the user, check that you saved it and that the Active checkbox is ticked.
If someone has left and you deactivated them, their name will not appear here, which is
correct: a deactivated user cannot sign in at all, so there is no role to remove.

**You gave someone a role and they still cannot see anything.** A role controls what a
person can do inside BarnCRM. It does not sign them in. Check that the person has a
Salesforce license in Setup, and that they are opening the BarnCRM app rather than
another app. If they see the app but no records, the records may be private and simply
owned by someone else, which is a sharing setting rather than a role.

**You see "This role is still being prepared. Wait a moment, reload the page, and try
again."** Salesforce rebuilds a role in the background whenever it changes, for example
just after the package is installed or upgraded, and it cannot hand the role out while that
rebuild is running. It usually finishes in under a minute. If you still see the message
after ten minutes, open the Error Log tile on the Hub home page and send what it says with
your support request.

**The Error Log says the BarnCRM Admin role was still being prepared at install.** The
entry reads "Warning: the BarnCRM Admin role was still being prepared after {0} attempts,
so it was not given to the person who installed BarnCRM. They already have the BarnCRM
Admin permission set, so BarnCRM Settings works. To finish, open BarnCRM Settings, then
Access, and give them the BarnCRM Admin role.", with the number of attempts in place of
{0}. Do what it says: on this page, give the installer the BarnCRM Admin role.

**You edited one of the shipped roles in Setup and now an upgrade has undone your change.**
The shipped roles (four with BarnCRM Core, and Fundraising Staff with the Giving module)
are replaced on every upgrade, so any change you make to them is lost. That is deliberate: it is what keeps the roles correct for you. If
your organization needs something extra, create your own permission set in Setup for just
that extra piece and assign it alongside the role. Your own permission sets are never
touched by an upgrade.

**You granted only the Manage BarnCRM Settings permission and saving a setting fails.**
The permission is what opens the settings console, but it is not the whole of what a save
needs: every setting that changes is written to a Setting Change record, so that the org can
answer who changed what and when, and that record is written as you rather than by the
package. Give the person the BarnCRM Admin role, which carries both. If your organization
builds its own permission set instead of using the role, it needs Create on Setting Change
and edit access on its five fields alongside the permission.

**You removed the BarnCRM Admin role from yourself.** The page will not let you remove
the last person holding BarnCRM Admin, and it warns you before you remove that role from
your own account. If you lose it anyway, anyone else with the BarnCRM Admin role, or a
Salesforce System Administrator working in Setup, can give it back to you.
