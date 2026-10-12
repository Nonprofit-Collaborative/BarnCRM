# Access: give a colleague access by name and role

## What it does

Access lets you give a colleague what they need to do their job by picking their name and
choosing a role, for example Program Staff or Read Only. You never have to learn what a
permission set is, and you never have to open Salesforce Setup to change someone's role. The
page also shows you, at a glance, who currently holds each role, so you can answer "who can
change our settings?" in a few seconds.

Roles ship with Open Impact and are kept up to date for you.

One thing they do not do yet. A role today carries what Core provides, and nothing a
module adds: the Giving module ships its own **Giving Admin**, **Giving Staff** and
**Giving Read Only** permission sets, and no role includes them. Until the Module Manager
in version 0.7 joins the two up, somebody with the Fundraising Staff role sees households
and people but no gifts, and a Salesforce administrator has to assign the module's
permission set in Setup alongside the role. That is the one place Open Impact still sends
you to Setup for access, and it is a gap rather than a design.

Open Impact Core ships four roles. The Fundraising Staff role comes with the Giving module,
so it is listed only where Giving is installed, which makes five:

| Role | Who it is for | What it gives |
|---|---|---|
| Open Impact Admin | The person who configures the app, usually you | Everything, including Open Impact Settings |
| Fundraising Staff (with Giving) | Development and fundraising staff | Day to day work with people, households, and giving |
| Program Staff | Program and services staff | Day to day work with people, households, and program records |
| Volunteer Coordinator | Whoever schedules and tracks volunteers | Day to day work with people, households, and volunteer records |
| Read Only | Board members, auditors, and anyone who should look but not change | Read access, no editing |

## Who can read a donor's receipts and tax statements

Nobody sees a receipt PDF unless they hold one of the Giving module's permission sets. This is
worth stating plainly, because a file in Salesforce is reached through the record it is attached
to, not through the record it is about.

| Person | What they hold | Can they open a receipt PDF |
|---|---|---|
| Maria, who configures Open Impact | Open Impact Admin, plus Giving Admin | Yes |
| David, who enters the gifts | Fundraising Staff, plus Giving Staff | Yes |
| Tom, on the board | Read Only, plus Giving Read Only | Yes, read only |
| Priya, who coordinates volunteers | Volunteer Coordinator, and no Giving set | No |
| Sam, in programs | Program Staff, and no Giving set | No |

Priya and Sam can open the donor's household and the donor's contact record, because that is
their job. What they cannot open is the receipt or the year-end statement, because a receipt PDF
is attached to the **Receipt** record and, for a single gift receipt, to the **Gift**, and both
of those need a Giving permission set. It is deliberately not attached to the household or the
contact: attaching it there would have handed every donor's tax history, and your organization's
tax identification number, to everyone who can read a contact.

So to find a donor's receipt, open the donor, then the **Receipts** related list, then the receipt,
then the file on it. If somebody says they cannot see receipts on a donor's record, that is this,
and the fix is the Giving permission set rather than anything on this page.

Nobody can edit or delete a receipt PDF, whatever they hold. See
[Receipts and year-end statements](receipts.md).

## How to turn it on

There is nothing to turn on. Access is part of Open Impact Core and appears in Open Impact
Settings as soon as the package is installed.

The person who installs Open Impact is given the Open Impact Admin role automatically, at
install and again at every upgrade, so there is always at least one person who can use this
page. If that person was you, you can start straight away.

Two things control who can use the page:

1. You need the Manage Open Impact Settings permission, which comes with the Open Impact Admin
   role. Anyone without it sees the page in read-only mode with a notice explaining why.
2. The person you are giving a role to must already be a Salesforce user with a license.
   Creating users is one of the few things Salesforce does not let an app do for you, so
   that step happens in Setup. See "What still needs Setup" below.

## A five-minute walkthrough

Maria has just hired David as Development Director. His Salesforce user already exists.
Here is how she gives him access, checks it, and takes it away again.

1. Open the Open Impact app and click the **Open Impact Settings** tab.
2. In the left navigation, choose **Access**. You see a card for each role (five with Giving,
   four without), each with a short description and the people who currently hold that role. On a fresh install only your
   own name appears, under Open Impact Admin.
3. In the **Find a person** box, type `David`. Matching active users appear as you type,
   each with their name and email address so you can tell two Davids apart.
4. Choose **David Okafor**.
5. Choose the role **Fundraising Staff** and click **Give access**. A confirmation asks you
   to confirm the person and the role. Click **Give access** again.
6. A message says "David Okafor now has the Fundraising Staff role." David's name appears
   on the Fundraising Staff card, and the number in brackets beside the role name goes up
   by one.
7. David can now sign in and see households and contacts. He does not see Open Impact
   Settings, because that belongs to the Open Impact Admin role, and he does not see gifts
   yet either: for those he also needs the Giving module's own **Giving Staff**
   permission set, which today is assigned in Salesforce Setup.
8. To take the role away, find David's name on the Fundraising Staff card and click
   **Remove**. Confirm, and a message says "David Okafor no longer has the Fundraising
   Staff role." His name disappears from the card.

A person can hold more than one role. Giving David the Program Staff role as well does not
remove Fundraising Staff, and removing one role leaves the other in place. Giving someone a
role they already have changes nothing and reports no error.

## What still needs Setup

Open Impact can give a person a role, but it cannot create the person or hand out a
Salesforce license. Only Salesforce Setup can do that, because licenses are billed and
managed by Salesforce rather than by an installed app.

So the order is always: create the user in Setup first, then give them a role here.

The **Create a user in Setup** link on the Access page opens the Users page in Setup in a
new tab. The address it opens is:

`/lightning/setup/ManageUsers/home`

Create the user with a Salesforce Platform or Salesforce license, save, then come back to
Access and search for their name.

## Common mistakes

**You cannot find the person in the search box.** The search only shows active users. If
you just created the user, check that you saved it and that the Active checkbox is ticked.
If someone has left and you deactivated them, their name will not appear here, which is
correct: a deactivated user cannot sign in at all, so there is no role to remove.

**You gave someone a role and they still cannot see anything.** A role controls what a
person can do inside Open Impact. It does not sign them in. Check that the person has a
Salesforce license in Setup, and that they are opening the Open Impact app rather than
another app. If they see the app but no records, the records may be private and simply
owned by someone else, which is a sharing setting rather than a role.

**You see "This role is still being prepared. Wait a moment, reload the page, and try
again."** Salesforce rebuilds a role in the background whenever it changes, for example
just after the package is installed or upgraded, and it cannot hand the role out while that
rebuild is running. It usually finishes in under a minute. If you still see the message
after ten minutes, open the Error Log tile on the Hub home page and send what it says with
your support request.

**You edited one of the shipped roles in Setup and now an upgrade has undone your change.**
The shipped roles (four with Open Impact Core, and Fundraising Staff with the Giving module)
are replaced on every upgrade, so any change you make to them is lost. That is deliberate: it is what keeps the roles correct for you. If
your organization needs something extra, create your own permission set in Setup for just
that extra piece and assign it alongside the role. Your own permission sets are never
touched by an upgrade.

**You granted only the Manage Open Impact Settings permission and saving a setting fails.**
The permission is what opens the settings console, but it is not the whole of what a save
needs: every setting that changes is written to a Setting Change record, so that the org can
answer who changed what and when, and that record is written as you rather than by the
package. Give the person the Open Impact Admin role, which carries both. If your organization
builds its own permission set instead of using the role, it needs Create on Setting Change
and edit access on its five fields alongside the permission.

**You removed the Open Impact Admin role from yourself.** The page will not let you remove
the last person holding Open Impact Admin, and it warns you before you remove that role from
your own account. If you lose it anyway, anyone else with the Open Impact Admin role, or a
Salesforce System Administrator working in Setup, can give it back to you.
